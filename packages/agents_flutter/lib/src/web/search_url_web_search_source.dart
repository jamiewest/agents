// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:math';

import 'web_page_html_renderer.dart';
import 'web_search_source.dart';
import 'web_search_tools.dart';
import 'package:extensions/system.dart';
import 'package:http/http.dart' as http;

import 'web_search_trace.dart';

/// A [WebSearchSource] that queries any search endpoint the user provides.
///
/// The request is the configured URL with the search terms appended as the
/// `q` query parameter, followed verbatim by [urlSuffix] —
/// `https://searx.example.com/search` with suffix `&format=json` becomes
/// `https://searx.example.com/search?q=my+search+terms&format=json` — so any
/// engine that takes `q` works: a self-hosted SearXNG instance, DuckDuckGo's
/// HTML endpoint, or anything else. Query parameters already present in the
/// configured URL (an instance key, a language pin) are preserved.
///
/// A JSON response (SearXNG's `format=json` shape: a top-level `results`
/// list of `url`/`title`/`content` objects) is parsed structurally,
/// including snippets. Anything else is treated as HTML, and results are the
/// links parsed from it with generic heuristics standing in for
/// provider-specific parsing:
///
/// - Redirect wrappers are unwrapped: a link whose query carries an absolute
///   `http(s)` URL (DuckDuckGo's `uddg`, Google's `/url?q=`) yields that
///   destination instead of the tracking hop.
/// - Links back to the search host itself — navigation, pagination,
///   preferences — are dropped, as are links with no text.
/// - Snippets are left empty — the model reads promising results with
///   `open_web_page`.
///
/// Server-rendered engines work as-is; an engine that only builds its
/// result list in JavaScript needs a [renderer], which runs the page in a
/// browser engine before the same parsing applies.
class SearchUrlWebSearchSource implements WebSearchSource {
  /// Creates a source that searches through [searchUrl].
  ///
  /// [httpClient] is injectable for tests; when omitted each call uses the
  /// default top-level client.
  SearchUrlWebSearchSource({
    required this.searchUrl,
    this.urlSuffix = '',
    this.userAgent,
    this.renderer,
    this.trace,
    this._httpClient,
  });

  /// The user-configured search endpoint, without the `q` parameter.
  final Uri searchUrl;

  /// User-configured URL text appended verbatim after the `q` parameter.
  ///
  /// A leading `&` is implied when missing, so `format=json` and
  /// `&format=json` configure the same request.
  final String urlSuffix;

  /// The `User-Agent` header sent with each request, or `null` to send the
  /// HTTP client's default.
  final String? userAgent;

  /// Renders the results page in a browser engine before parsing, for
  /// engines that build their results with JavaScript; `null` fetches the
  /// page over plain HTTP.
  final WebPageHtmlRenderer? renderer;

  /// Receives one event per search request — the exact URL, user agent,
  /// status, and response — or `null` to trace nothing.
  final WebSearchTraceLog? trace;

  final http.Client? _httpClient;

  static final RegExp _anchorPattern = RegExp(
    r'''<a\s[^>]*href\s*=\s*["']([^"']*)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  @override
  Future<Iterable<WebSearchResult>> search(
    String query, {
    required int maxResults,
    CancellationToken? cancellationToken,
  }) async {
    final url = _requestUrl(query);
    cancellationToken?.throwIfCancellationRequested();
    final watch = Stopwatch()..start();
    if (renderer case final renderer?) {
      // Ready once a snapshot parses to a few results: interstitials like
      // Google's enable-JavaScript page leave at most a stray support link,
      // while a genuinely short result list still arrives through the last
      // snapshot when the renderer's budget runs out.
      final RenderedWebPage page;
      try {
        page = await renderer.render(
          url,
          userAgent: userAgent,
          isReady: (page) =>
              _parseHtmlResults(page.html, page.url, maxResults).length >=
              min(3, maxResults),
        );
      } catch (error) {
        _recordError(query, url, 'renderer', error, watch);
        rethrow;
      }
      cancellationToken?.throwIfCancellationRequested();
      final results = _parseHtmlResults(page.html, page.url, maxResults);
      trace?.record(
        WebSearchTraceEvent(
          tool: webSearchToolName,
          transport: 'renderer',
          query: query,
          requestUrl: url,
          userAgent: userAgent,
          finalUrl: page.url,
          outcome: 'success',
          resultCount: results.length,
          responseBody: WebSearchTraceLog.cappedBody(page.html),
          responseTruncated:
              page.html.length > WebSearchTraceLog.maxBodyCharacters,
          duration: watch.elapsed,
          capturedAt: DateTime.now(),
        ),
      );
      return results;
    }
    final headers = userAgent == null ? null : {'User-Agent': userAgent!};
    final http.Response response;
    try {
      response = _httpClient == null
          ? await http.get(url, headers: headers)
          : await _httpClient.get(url, headers: headers);
    } catch (error) {
      _recordError(query, url, 'http', error, watch);
      rethrow;
    }
    cancellationToken?.throwIfCancellationRequested();
    final body = response.body;
    final ok = response.statusCode == 200;
    final results = !ok
        ? const <WebSearchResult>[]
        : body.trimLeft().startsWith('{')
        ? _parseJsonResults(body, maxResults)
        : _parseHtmlResults(body, response.request?.url ?? url, maxResults);
    trace?.record(
      WebSearchTraceEvent(
        tool: webSearchToolName,
        transport: 'http',
        query: query,
        requestUrl: url,
        userAgent: userAgent,
        finalUrl: response.request?.url,
        outcome: ok ? 'success' : 'httpError',
        httpStatusCode: response.statusCode,
        resultCount: ok ? results.length : null,
        responseBody: WebSearchTraceLog.cappedBody(body),
        responseTruncated: body.length > WebSearchTraceLog.maxBodyCharacters,
        duration: watch.elapsed,
        capturedAt: DateTime.now(),
      ),
    );
    if (!ok) {
      throw http.ClientException(
        'The search endpoint returned HTTP ${response.statusCode}.',
        url,
      );
    }
    return results;
  }

  /// Records a failed search request into [trace].
  void _recordError(
    String query,
    Uri url,
    String transport,
    Object error,
    Stopwatch watch,
  ) => trace?.record(
    WebSearchTraceEvent(
      tool: webSearchToolName,
      transport: transport,
      query: query,
      requestUrl: url,
      userAgent: userAgent,
      outcome: 'error',
      error: error.toString(),
      duration: watch.elapsed,
      capturedAt: DateTime.now(),
    ),
  );

  /// The configured URL with `q` and then [urlSuffix] appended.
  ///
  /// Built textually rather than through [Uri.replace] so the stored URL and
  /// the suffix reach the engine exactly as the user wrote them.
  Uri _requestUrl(String query) {
    final base = searchUrl.toString();
    final separator = !base.contains('?')
        ? '?'
        : base.endsWith('?') || base.endsWith('&')
        ? ''
        : '&';
    var suffix = urlSuffix.trim();
    if (suffix.isNotEmpty &&
        !suffix.startsWith('&') &&
        !suffix.startsWith('#')) {
      suffix = '&$suffix';
    }
    return Uri.parse(
      '$base${separator}q=${Uri.encodeQueryComponent(query)}$suffix',
    );
  }

  /// Parses a SearXNG-style JSON body: a top-level `results` list of
  /// `url`/`title`/`content` objects. Other JSON shapes yield no results.
  static Iterable<WebSearchResult> _parseJsonResults(
    String body,
    int maxResults,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const <WebSearchResult>[];
    }
    final entries = decoded is Map ? decoded['results'] : null;
    if (entries is! List) return const <WebSearchResult>[];
    final results = <WebSearchResult>[];
    for (final entry in entries) {
      if (results.length >= maxResults) break;
      if (entry is! Map) continue;
      final url = (entry['url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      results.add(
        WebSearchResult(
          title: (entry['title'] ?? '').toString(),
          url: url,
          snippet: (entry['content'] ?? '').toString(),
        ),
      );
    }
    return results;
  }

  /// Parses result links out of an HTML body.
  static Iterable<WebSearchResult> _parseHtmlResults(
    String body,
    Uri base,
    int maxResults,
  ) {
    final seen = <String>{};
    final results = <WebSearchResult>[];
    for (final match in _anchorPattern.allMatches(body)) {
      if (results.length >= maxResults) break;
      final resolved = _resolveResultUrl(base, match.group(1) ?? '');
      if (resolved == null || resolved.host == base.host) continue;
      final title = _plainText(match.group(2) ?? '');
      if (title.isEmpty || !seen.add(resolved.toString())) continue;
      results.add(WebSearchResult(title: title, url: resolved.toString()));
    }
    return results;
  }

  /// Resolves [href] against [base] and unwraps redirect links, returning
  /// `null` for anything that is not a plain `http(s)` destination.
  static Uri? _resolveResultUrl(Uri base, String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    Uri resolved;
    try {
      resolved = base.resolve(trimmed);
    } on FormatException {
      return null;
    }
    // A result link whose query carries an absolute web URL is a redirect
    // wrapper; the embedded destination is the real result.
    for (final value in resolved.queryParameters.values) {
      final embedded = Uri.tryParse(value);
      if (embedded != null &&
          (embedded.scheme == 'http' || embedded.scheme == 'https') &&
          embedded.hasAuthority) {
        resolved = embedded;
        break;
      }
    }
    final isWebUrl =
        (resolved.scheme == 'http' || resolved.scheme == 'https') &&
        resolved.hasAuthority;
    return isWebUrl ? resolved : null;
  }
}

/// Reduces anchor inner HTML to plain text.
///
/// Result titles arrive with highlight tags, entity-encoded characters, and
/// layout whitespace; the model wants none of them.
String _plainText(String value) => value
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
