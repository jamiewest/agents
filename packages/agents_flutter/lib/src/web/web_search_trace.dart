// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../configured_agents/storage/key_value_store.dart';
import 'web_page_loader.dart';
import 'web_search_tools.dart';
import 'package:extensions/system.dart';
import 'package:flutter/foundation.dart';

/// One traced web tool call: the HTTP details of what was sent and what
/// came back.
///
/// Captured for both `web_search` (the request to the configured search
/// endpoint) and `open_web_page` (the headless page load). [responseBody]
/// holds the data the tool worked from — the raw search response for
/// searches, the extracted page text for page loads — capped at
/// [WebSearchTraceLog.maxBodyCharacters].
@immutable
class WebSearchTraceEvent {
  /// Creates a trace event.
  const WebSearchTraceEvent({
    required this.tool,
    required this.transport,
    required this.requestUrl,
    required this.outcome,
    required this.duration,
    required this.capturedAt,
    this.query,
    this.userAgent,
    this.httpStatusCode,
    this.finalUrl,
    this.resultCount,
    this.responseBody = '',
    this.responseTruncated = false,
    this.error,
  });

  /// The tool that made the call: `web_search` or `open_web_page`.
  final String tool;

  /// How the request went out: `http` (plain GET), `renderer` (hidden
  /// browser engine running the page's JavaScript), or `webview` (the
  /// headless page loader).
  final String transport;

  /// The search query, for `web_search` calls.
  final String? query;

  /// The full request URL, query string included.
  final Uri requestUrl;

  /// The `User-Agent` header sent, or `null` for the client's default.
  final String? userAgent;

  /// The response HTTP status, when one was observed.
  final int? httpStatusCode;

  /// The URL the response came from, when redirects moved it off
  /// [requestUrl].
  final Uri? finalUrl;

  /// Short outcome label: `success`, an error category, or the page-load
  /// status name.
  final String outcome;

  /// Parsed search results, for `web_search` calls.
  final int? resultCount;

  /// The received data, capped at [WebSearchTraceLog.maxBodyCharacters].
  final String responseBody;

  /// Whether [responseBody] was capped.
  final bool responseTruncated;

  /// The thrown error, when the call failed.
  final String? error;

  /// How long the call took.
  final Duration duration;

  /// When the event was recorded.
  final DateTime capturedAt;

  /// A short one-line label for lists: the query or the request URL.
  String get title => query ?? requestUrl.toString();

  /// Renders every captured detail as copyable text.
  String describe() {
    final buffer = StringBuffer()
      ..writeln('Tool: $tool')
      ..writeln('Time: $capturedAt')
      ..writeln(
        'Outcome: $outcome'
        '${httpStatusCode == null ? '' : ' · HTTP $httpStatusCode'}'
        ' · ${duration.inMilliseconds} ms',
      )
      ..writeln('Transport: $transport');
    if (query != null) buffer.writeln('Query: $query');
    buffer
      ..writeln('Request: GET $requestUrl')
      ..writeln('User-Agent: ${userAgent ?? '(default)'}');
    if (finalUrl != null && finalUrl.toString() != requestUrl.toString()) {
      buffer.writeln('Final URL: $finalUrl');
    }
    if (resultCount != null) buffer.writeln('Results: $resultCount');
    if (error != null) buffer.writeln('Error: $error');
    if (responseBody.isNotEmpty) {
      buffer
        ..writeln(
          '--- Response (${responseBody.length} chars'
          '${responseTruncated ? ', truncated' : ''}) ---',
        )
        ..write(responseBody);
    }
    return buffer.toString();
  }
}

/// A rolling, in-memory log of web tool HTTP traffic, with a persisted
/// on/off switch.
///
/// Both capture points — `SearchUrlWebSearchSource` for searches and
/// [TracingWebPageLoader] for page opens — feed this single store, so the
/// Settings inspector shows every web request together, newest first.
/// [record] drops events while tracing is off, so the capture points stay
/// wired unconditionally and the toggle takes effect immediately, without
/// rebuilding agents. Events never persist: only the toggle survives a
/// restart.
class WebSearchTraceLog extends ChangeNotifier {
  /// Creates a trace log.
  ///
  /// [keyValueStore] persists the enabled flag; omit it (tests) to keep
  /// the flag in memory only.
  WebSearchTraceLog({this._keyValueStore});

  /// The key persisting the enabled flag.
  static const String enabledKey = 'agents_app.web_search.trace_enabled';

  /// The most recent events kept before the oldest is dropped.
  static const int maxEvents = 100;

  /// The response-body cap per event, so a large page cannot pin
  /// megabytes of memory.
  static const int maxBodyCharacters = 64 * 1024;

  final KeyValueStore? _keyValueStore;
  final List<WebSearchTraceEvent> _events = <WebSearchTraceEvent>[];
  bool _enabled = false;

  /// Whether calls are currently recorded.
  bool get isEnabled => _enabled;

  /// Captured events, most recent first.
  List<WebSearchTraceEvent> get events =>
      List<WebSearchTraceEvent>.unmodifiable(_events.reversed);

  /// Loads the persisted enabled flag.
  Future<void> load() async {
    _enabled = await _keyValueStore?.read(enabledKey) == 'true';
    notifyListeners();
  }

  /// Turns tracing on or off and persists the choice.
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    if (value) {
      await _keyValueStore?.write(enabledKey, 'true');
    } else {
      await _keyValueStore?.delete(enabledKey);
    }
  }

  /// Records [event] and notifies listeners; a no-op while tracing is off.
  void record(WebSearchTraceEvent event) {
    if (!_enabled) return;
    _events.add(event);
    if (_events.length > maxEvents) _events.removeAt(0);
    notifyListeners();
  }

  /// Discards all captured events.
  void clear() {
    if (_events.isEmpty) return;
    _events.clear();
    notifyListeners();
  }

  /// Caps [body] at [maxBodyCharacters] for storing in an event.
  static String cappedBody(String body) => body.length <= maxBodyCharacters
      ? body
      : body.substring(0, maxBodyCharacters);
}

/// A [WebPageLoader] that mirrors each `open_web_page` load into a
/// [WebSearchTraceLog] before handing back the inner loader's result.
///
/// The page's HTTP details live inside the platform WebView, so the event
/// records what crosses this seam: the requested and final URLs, the load
/// status and HTTP error code when one was observed, and the extracted
/// text the model receives.
class TracingWebPageLoader implements WebPageLoader {
  /// Creates a loader that traces [_inner]'s loads into [_log].
  ///
  /// [userAgent] is recorded on each event when the inner loader sends a
  /// custom browsing user agent; `null` records the platform default.
  TracingWebPageLoader(this._inner, this._log, {this.userAgent});

  /// The `User-Agent` the inner loader sends, or `null` for the default.
  final String? userAgent;

  final WebPageLoader _inner;
  final WebSearchTraceLog _log;

  @override
  Future<WebPageContent> load(
    Uri url, {
    CancellationToken? cancellationToken,
  }) async {
    final watch = Stopwatch()..start();
    final WebPageContent content;
    try {
      content = await _inner.load(url, cancellationToken: cancellationToken);
    } catch (error) {
      _log.record(
        WebSearchTraceEvent(
          tool: openWebPageToolName,
          transport: 'webview',
          requestUrl: url,
          userAgent: userAgent,
          outcome: 'error',
          error: error.toString(),
          duration: watch.elapsed,
          capturedAt: DateTime.now(),
        ),
      );
      rethrow;
    }
    final body = [
      if (content.title case final title?) 'Title: $title',
      if (content.description case final description?)
        'Description: $description',
      if (content.text.isNotEmpty) content.text,
      if (content.message case final message?) 'Message: $message',
    ].join('\n');
    _log.record(
      WebSearchTraceEvent(
        tool: openWebPageToolName,
        transport: 'webview',
        requestUrl: url,
        userAgent: userAgent,
        finalUrl: content.finalUrl,
        outcome: content.status.name,
        httpStatusCode: content.httpStatusCode,
        responseBody: WebSearchTraceLog.cappedBody(body),
        responseTruncated:
            content.truncated ||
            body.length > WebSearchTraceLog.maxBodyCharacters,
        duration: watch.elapsed,
        capturedAt: DateTime.now(),
      ),
    );
    return content;
  }
}
