import 'dart:async';
import 'dart:convert';

import 'package:extensions/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'web_navigation_policy.dart';
import 'web_page_extraction.dart';
import 'web_page_loader.dart';
import 'web_page_renderer.dart';
import 'web_search_tool_options.dart';

/// Loads pages in a fresh, off-screen system WebView.
///
/// Each call uses incognito mode and disposes the native WebView before the
/// future completes. This class never reads or clears the process-wide WebView
/// cookie store.
class HeadlessWebViewPageLoader implements WebPageLoader {
  /// Creates a headless page loader.
  HeadlessWebViewPageLoader({
    WebNavigationPolicy? navigationPolicy,
    WebSearchToolOptions? options,
    this.userAgent,
  }) : _navigationPolicy = navigationPolicy ?? PublicWebNavigationPolicy(),
       _options = options ?? WebSearchToolOptions() {
    _options.validate();
  }

  /// The `User-Agent` sent with page loads, or `null` for the platform
  /// WebView's default (which may identify the client as an embedded
  /// WebView).
  final String? userAgent;

  final WebNavigationPolicy _navigationPolicy;
  final WebSearchToolOptions _options;

  @override
  Future<WebPageContent> load(
    Uri url, {
    CancellationToken? cancellationToken,
  }) async {
    final unsupported = _unsupportedMessage();
    if (unsupported != null) {
      return WebPageContent(
        status: WebPageLoadStatus.unsupported,
        requestedUrl: url,
        message: unsupported,
      );
    }

    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    final initialDecision = await _evaluate(url);
    token.throwIfCancellationRequested();
    if (!initialDecision.allowed) {
      return WebPageContent(
        status: WebPageLoadStatus.blocked,
        requestedUrl: url,
        message: initialDecision.reason,
      );
    }

    final result = Completer<WebPageContent>();
    var finished = false;
    InAppWebViewController? controller;
    HeadlessInAppWebView? webView;

    void complete(WebPageContent content) {
      if (finished || result.isCompleted) return;
      result.complete(content);
    }

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (finished || result.isCompleted) return;
      result.completeError(error, stackTrace);
    }

    Future<void> extractPage(
      InAppWebViewController pageController,
      WebUri? callbackUrl,
    ) async {
      await Future<void>.delayed(_options.domSettleDelay);
      if (finished || result.isCompleted) return;
      token.throwIfCancellationRequested();

      final browserUrl = await pageController.getUrl();
      final finalUrl = _toUri(browserUrl ?? callbackUrl) ?? url;
      final finalDecision = await _evaluate(finalUrl);
      if (!finalDecision.allowed) {
        complete(
          WebPageContent(
            status: WebPageLoadStatus.blocked,
            requestedUrl: url,
            finalUrl: finalUrl,
            message: finalDecision.reason,
          ),
        );
        return;
      }

      try {
        final raw = await pageController.evaluateJavascript(
          source: _extractionScript,
        );
        final extracted = _decodeExtraction(raw);
        complete(_buildContent(url, finalUrl, extracted));
      } on OperationCanceledException catch (error, stackTrace) {
        completeError(error, stackTrace);
      } catch (_) {
        complete(
          WebPageContent(
            status: WebPageLoadStatus.loadError,
            requestedUrl: url,
            finalUrl: finalUrl,
            message: 'The page loaded, but its content could not be read.',
          ),
        );
      }
    }

    webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri.uri(url),
        httpShouldHandleCookies: true,
      ),
      initialSettings: InAppWebViewSettings(
        incognito: true,
        cacheEnabled: false,
        userAgent: (userAgent?.trim().isEmpty ?? true)
            ? null
            : userAgent!.trim(),
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        safeBrowsingEnabled: true,
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        supportMultipleWindows: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        useOnDownloadStart: true,
        geolocationEnabled: false,
        thirdPartyCookiesEnabled: false,
        sharedCookiesEnabled: false,
        saveFormData: false,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: false,
        allowsPictureInPictureMediaPlayback: false,
        supportZoom: false,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (created) => controller = created,
      onLoadStop: (pageController, loadedUrl) {
        unawaited(extractPage(pageController, loadedUrl));
      },
      shouldOverrideUrlLoading: (pageController, action) async {
        final target = _toUri(action.request.url);
        if (target == null) {
          if (action.isForMainFrame) {
            complete(
              WebPageContent(
                status: WebPageLoadStatus.blocked,
                requestedUrl: url,
                message: 'The page attempted to navigate to an invalid URL.',
              ),
            );
          }
          return NavigationActionPolicy.CANCEL;
        }

        final decision = await _evaluate(target);
        if (!decision.allowed) {
          if (action.isForMainFrame) {
            complete(
              WebPageContent(
                status: WebPageLoadStatus.blocked,
                requestedUrl: url,
                finalUrl: target,
                message: decision.reason,
              ),
            );
          }
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      shouldInterceptRequest: (pageController, request) async {
        final target = _toUri(request.url);
        final decision = target == null
            ? const WebNavigationDecision.block('Invalid resource URL.')
            : await _evaluate(target);
        if (decision.allowed) return null;

        if (request.isForMainFrame != false) {
          complete(
            WebPageContent(
              status: WebPageLoadStatus.blocked,
              requestedUrl: url,
              finalUrl: target,
              message: decision.reason,
            ),
          );
        }
        return WebResourceResponse(
          contentType: 'text/plain',
          contentEncoding: 'utf-8',
          data: Uint8List(0),
          statusCode: 403,
          reasonPhrase: 'Blocked',
          headers: const <String, String>{},
        );
      },
      onReceivedError: (pageController, request, error) {
        if (request.isForMainFrame == false) return;
        complete(
          WebPageContent(
            status: WebPageLoadStatus.loadError,
            requestedUrl: url,
            finalUrl: _toUri(request.url),
            message: 'The browser could not load the page.',
          ),
        );
      },
      onReceivedHttpError: (pageController, request, response) {
        if (request.isForMainFrame == false) return;
        complete(
          WebPageContent(
            status: WebPageLoadStatus.httpError,
            requestedUrl: url,
            finalUrl: _toUri(request.url),
            httpStatusCode: response.statusCode,
            message: response.statusCode == null
                ? 'The page returned an HTTP error.'
                : 'The page returned HTTP ${response.statusCode}.',
          ),
        );
      },
      onDownloadStartRequest: (pageController, request) {
        complete(
          WebPageContent(
            status: WebPageLoadStatus.loadError,
            requestedUrl: url,
            finalUrl: _toUri(request.url),
            message: 'The URL started a download instead of a readable page.',
          ),
        );
      },
      onCreateWindow: (pageController, action) async => false,
      onPermissionRequest: (pageController, request) async =>
          PermissionResponse(
            action: PermissionResponseAction.DENY,
            resources: request.resources,
          ),
      onGeolocationPermissionsShowPrompt: (pageController, origin) async =>
          GeolocationPermissionShowPromptResponse(
            origin: origin,
            allow: false,
            retain: false,
          ),
      onReceivedHttpAuthRequest: (pageController, challenge) async =>
          HttpAuthResponse(action: HttpAuthResponseAction.CANCEL),
      onReceivedClientCertRequest: (pageController, challenge) async =>
          ClientCertResponse(
            certificatePath: '',
            action: ClientCertResponseAction.CANCEL,
          ),
      onJsAlert: (pageController, request) async => JsAlertResponse(
        handledByClient: true,
        action: JsAlertResponseAction.CONFIRM,
      ),
      onJsConfirm: (pageController, request) async => JsConfirmResponse(
        handledByClient: true,
        action: JsConfirmResponseAction.CANCEL,
      ),
      onJsPrompt: (pageController, request) async => JsPromptResponse(
        handledByClient: true,
        action: JsPromptResponseAction.CANCEL,
      ),
    );

    final registration = token.register((_) {
      unawaited(controller?.stopLoading());
      completeError(OperationCanceledException(cancellationToken: token));
    });

    try {
      await webView.run();
      final timeout = Future<WebPageContent>.delayed(
        _options.pageLoadTimeout,
        () => WebPageContent(
          status: WebPageLoadStatus.timeout,
          requestedUrl: url,
          message: 'The page did not finish loading before the timeout.',
        ),
      );
      final content = await Future.any(<Future<WebPageContent>>[
        result.future,
        timeout,
      ]);
      finished = true;
      return content;
    } on OperationCanceledException {
      rethrow;
    } catch (_) {
      return WebPageContent(
        status: WebPageLoadStatus.loadError,
        requestedUrl: url,
        message: 'The headless browser could not be started.',
      );
    } finally {
      finished = true;
      registration.dispose();
      try {
        await controller?.stopLoading();
      } catch (_) {
        // Best-effort shutdown; disposal below owns final cleanup.
      }
      try {
        await webView.dispose();
      } catch (_) {
        // The native view was already stopped; do not replace the load result
        // with a platform cleanup error.
      }
    }
  }

  Future<WebNavigationDecision> _evaluate(Uri url) async {
    try {
      return await _navigationPolicy.evaluate(url);
    } on UnsupportedError {
      rethrow;
    } catch (_) {
      return const WebNavigationDecision.block(
        'The destination could not be verified as a public web address.',
      );
    }
  }

  WebPageContent _buildContent(
    Uri requestedUrl,
    Uri finalUrl,
    Map<String, Object?> extracted,
  ) {
    final extraction = WebPageExtraction.parse(extracted);
    final rawText = extraction.plainText.trim();
    final textCapped = rawText.length > _options.maxPageCharacters;
    final text = textCapped
        ? rawText.substring(0, _options.maxPageCharacters)
        : rawText;
    final rendered = extraction.blocks.isEmpty
        ? null
        : renderWebPageMarkdown(
            extraction: extraction,
            sourceUrl: finalUrl,
            maxCharacters: _options.maxPageCharacters,
          );
    final challenge = extraction.challenge;
    final empty = (rendered?.markdown.isEmpty ?? true) && text.isEmpty;
    final status = challenge
        ? WebPageLoadStatus.challengeDetected
        : empty
        ? WebPageLoadStatus.emptyContent
        : WebPageLoadStatus.success;

    return WebPageContent(
      status: status,
      requestedUrl: requestedUrl,
      finalUrl: finalUrl,
      title: extraction.title,
      canonicalUrl: _tryParseUri(extraction.canonicalUrl),
      description: extraction.description,
      text: text,
      truncated:
          textCapped ||
          extraction.omittedBlocks > 0 ||
          (rendered?.omittedForBudget ?? 0) > 0,
      blocks: extraction.blocks,
      outline: extraction.outline,
      structuredData: extraction.structuredData,
      siteName: extraction.siteName,
      publishedTime: extraction.published,
      modifiedTime: extraction.modified,
      author: extraction.author,
      contentMarkdown: rendered?.markdown,
      omittedBlocks:
          extraction.omittedBlocks + (rendered?.omittedForBudget ?? 0),
      scriptOmittedBlocks: extraction.omittedBlocks,
      boilerplateBlocks: rendered?.boilerplateBlocks ?? 0,
      duplicateBlocks: extraction.blocks
          .where(
            (block) => !block.isBoilerplate && block.duplicateOfIndex != null,
          )
          .length,
      message: challenge
          ? 'The page appears to require login, consent, CAPTCHA, or human verification.'
          : empty
          ? 'The page contained no readable text.'
          : null,
    );
  }

  static Map<String, Object?> _decodeExtraction(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      throw const FormatException('Unexpected page extraction result.');
    }
    return <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static Uri? _tryParseUri(String? value) =>
      value == null ? null : Uri.tryParse(value);

  static Uri? _toUri(Uri? value) =>
      value == null ? null : Uri.tryParse(value.toString());

  static String? _unsupportedMessage() {
    if (kIsWeb) {
      return 'Headless page loading is not supported on Flutter web.';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => null,
      _ =>
        'Headless page loading is supported on Android, iOS, macOS, and Windows.',
    };
  }

  /// A thin DOM walker: it emits raw typed blocks with container context
  /// plus page metadata and JSON-LD payloads, all capped in-script because
  /// the JavaScript bridge bounds result sizes. Classification, heading
  /// paths, outlines, and rendering happen in Dart (`WebPageExtraction`),
  /// where they are testable without a WebView.
  static const String _extractionScript = r'''
(() => {
  const MAX_BLOCKS = 500;
  const MAX_TEXT = 6000;
  const MAX_ITEMS = 40;
  const MAX_ITEM_TEXT = 300;
  const MAX_ROWS = 30;
  const MAX_COLS = 12;
  const MAX_CELL = 120;
  const MAX_LINKS = 10;
  const MAX_LINK_TEXT = 80;
  const MAX_STRUCTURED = 5;
  const MAX_STRUCTURED_TEXT = 20000;

  const clean = (value) => (value || '')
    .replace(/\r/g, '')
    .replace(/[ \t\u00a0]+/g, ' ')
    .replace(/\s*\n\s*/g, '\n')
    .trim();
  const capped = (value, max) => {
    const text = clean(value);
    return text.length > max ? text.slice(0, max) : text;
  };

  const blocks = [];
  let total = 0;
  const emit = (block) => {
    total += 1;
    if (blocks.length < MAX_BLOCKS) blocks.push(block);
  };

  const hidden = (el) => {
    if (el.getAttribute('aria-hidden') === 'true' || el.hasAttribute('hidden')) {
      return true;
    }
    const style = window.getComputedStyle ? window.getComputedStyle(el) : null;
    return !!style && (style.display === 'none' || style.visibility === 'hidden');
  };

  const containerOf = (tag, role, current) => {
    if (tag === 'NAV' || role === 'navigation') return 'nav';
    if (tag === 'HEADER' || role === 'banner') return 'header';
    if (tag === 'FOOTER' || role === 'contentinfo') return 'footer';
    if (tag === 'ASIDE' || role === 'complementary') return 'aside';
    if (tag === 'MAIN' || tag === 'ARTICLE' || role === 'main') return 'main';
    return current;
  };

  const pathOf = (el) => {
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && node !== document.body && parts.length < 6) {
      let index = 1;
      let sibling = node.previousElementSibling;
      while (sibling) {
        if (sibling.tagName === node.tagName) index += 1;
        sibling = sibling.previousElementSibling;
      }
      parts.unshift(node.tagName.toLowerCase() + (index > 1 ? ':' + index : ''));
      node = node.parentElement;
    }
    return parts.join('>');
  };

  const linksOf = (el) => {
    const links = [];
    for (const anchor of el.querySelectorAll('a[href]')) {
      if (links.length >= MAX_LINKS) break;
      const href = anchor.href || '';
      if (!/^https?:/i.test(href)) continue;
      links.push({ t: capped(anchor.innerText, MAX_LINK_TEXT), h: href });
    }
    return links;
  };

  const emitText = (kind, el, container, extra) => {
    const text = kind === 'code'
      ? (el.innerText || '').replace(/\r/g, '').trim().slice(0, MAX_TEXT)
      : capped(el.innerText, MAX_TEXT);
    if (!text) return;
    emit(Object.assign(
      { kind, text, container, path: pathOf(el), links: linksOf(el) },
      extra || {}));
  };

  const emitList = (el, container, ordered) => {
    const items = [];
    for (const li of el.children) {
      if (li.tagName !== 'LI' || items.length >= MAX_ITEMS) continue;
      const text = capped(li.innerText, MAX_ITEM_TEXT);
      if (text) items.push(text);
    }
    if (!items.length) return;
    emit({ kind: 'list', text: '', ordered: !!ordered, items,
      container, path: pathOf(el), links: linksOf(el) });
  };

  const emitDefinitions = (el, container) => {
    const items = [];
    let term = '';
    for (const child of el.children) {
      if (child.tagName === 'DT') term = capped(child.innerText, MAX_ITEM_TEXT);
      if (child.tagName === 'DD' && items.length < MAX_ITEMS) {
        const def = capped(child.innerText, MAX_ITEM_TEXT);
        if (term || def) items.push((term ? term + ' — ' : '') + def);
      }
    }
    if (items.length) {
      emit({ kind: 'definition', text: '', items, container, path: pathOf(el) });
    }
  };

  const emitTable = (el, container) => {
    const caption = el.caption ? capped(el.caption.innerText, MAX_ITEM_TEXT) : '';
    const headRow = el.tHead && el.tHead.rows.length ? el.tHead.rows[0] : null;
    const columns = [];
    if (headRow) {
      for (const cell of headRow.cells) {
        if (columns.length < MAX_COLS) columns.push(capped(cell.innerText, MAX_CELL));
      }
    }
    const rows = [];
    for (const tr of el.rows) {
      if (tr === headRow) continue;
      if (rows.length >= MAX_ROWS) break;
      const cells = Array.from(tr.cells);
      const texts = cells.slice(0, MAX_COLS).map((c) => capped(c.innerText, MAX_CELL));
      if (!columns.length && cells.length && cells.every((c) => c.tagName === 'TH')) {
        columns.push(...texts);
        continue;
      }
      if (texts.some((t) => t)) rows.push(texts);
    }
    if (!columns.length && !rows.length) return;
    emit({ kind: 'table', text: '',
      table: { caption, columns, rows },
      container, path: pathOf(el), links: linksOf(el) });
  };

  const emitForm = (el, container) => {
    const parts = [];
    for (const label of el.querySelectorAll('label')) {
      if (parts.length >= MAX_ITEMS) break;
      const text = capped(label.innerText, MAX_ITEM_TEXT);
      if (text) parts.push(text);
    }
    for (const field of el.querySelectorAll('input[placeholder], textarea[placeholder]')) {
      if (parts.length >= MAX_ITEMS) break;
      const text = capped(field.getAttribute('placeholder'), MAX_ITEM_TEXT);
      if (text) parts.push(text);
    }
    for (const button of el.querySelectorAll('button, input[type="submit"]')) {
      if (parts.length >= MAX_ITEMS) break;
      const text = capped(button.innerText || button.value, MAX_ITEM_TEXT);
      if (text) parts.push('[' + text + ']');
    }
    if (parts.length) {
      emit({ kind: 'form', text: parts.join(' · '), container, path: pathOf(el) });
    }
  };

  const INLINE = new Set(['A', 'B', 'I', 'EM', 'STRONG', 'SPAN', 'CODE',
    'SMALL', 'SUB', 'SUP', 'MARK', 'ABBR', 'TIME', 'U', 'S', 'LABEL',
    'BR', 'WBR', 'IMG', 'PICTURE', 'SOURCE']);
  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'IFRAME',
    'CANVAS', 'SVG', 'VIDEO', 'AUDIO', 'OBJECT', 'EMBED', 'SELECT',
    'OPTION', 'DIALOG', 'BUTTON', 'INPUT', 'TEXTAREA', 'LINK', 'META']);

  const walk = (el, container) => {
    let inlineText = [];
    let inlineLinks = [];
    const flush = () => {
      const text = capped(inlineText.join(' '), MAX_TEXT);
      const links = inlineLinks.slice(0, MAX_LINKS);
      inlineText = [];
      inlineLinks = [];
      if (text) {
        emit({ kind: 'paragraph', text, container, path: pathOf(el), links });
      }
    };
    for (const node of el.childNodes) {
      if (node.nodeType === 3) {
        const text = clean(node.textContent);
        if (text) inlineText.push(text);
        continue;
      }
      if (node.nodeType !== 1) continue;
      const tag = node.tagName;
      if (SKIP.has(tag) || hidden(node)) continue;
      if (INLINE.has(tag)) {
        if (tag === 'IMG') {
          const alt = clean(node.getAttribute('alt'));
          if (alt) {
            emit({ kind: 'media', text: alt.slice(0, MAX_ITEM_TEXT),
              container, path: pathOf(node) });
          }
          continue;
        }
        if (tag === 'A' && /^https?:/i.test(node.href || '') &&
            inlineLinks.length < MAX_LINKS) {
          inlineLinks.push({ t: capped(node.innerText, MAX_LINK_TEXT), h: node.href });
        }
        const text = clean(node.innerText);
        if (text) inlineText.push(text);
        continue;
      }
      flush();
      const childContainer = containerOf(tag, node.getAttribute('role') || '', container);
      if (/^H[1-6]$/.test(tag)) {
        emitText('heading', node, childContainer, { level: +tag[1] });
      } else if (tag === 'P' || tag === 'FIGCAPTION') {
        emitText('paragraph', node, childContainer);
      } else if (tag === 'UL' || tag === 'OL' || tag === 'MENU') {
        emitList(node, childContainer, tag === 'OL');
      } else if (tag === 'DL') {
        emitDefinitions(node, childContainer);
      } else if (tag === 'TABLE') {
        emitTable(node, childContainer);
      } else if (tag === 'PRE') {
        emitText('code', node, childContainer);
      } else if (tag === 'BLOCKQUOTE') {
        emitText('quote', node, childContainer);
      } else if (tag === 'FORM') {
        emitForm(node, childContainer);
      } else {
        walk(node, childContainer);
      }
    }
    flush();
  };

  walk(document.body, '');

  const metaContent = (selector) => {
    const el = document.querySelector(selector);
    return el ? clean(el.getAttribute('content')) : '';
  };
  const canonical = document.querySelector('link[rel~="canonical"]');
  const meta = {
    title: clean(document.title),
    canonicalUrl: canonical ? canonical.href : '',
    description: metaContent('meta[name="description"]') ||
      metaContent('meta[property="og:description"]'),
    siteName: metaContent('meta[property="og:site_name"]'),
    published: metaContent('meta[property="article:published_time"]') ||
      metaContent('meta[itemprop="datePublished"]'),
    modified: metaContent('meta[property="article:modified_time"]') ||
      metaContent('meta[itemprop="dateModified"]'),
    author: metaContent('meta[name="author"]')
  };

  const structured = [];
  for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
    if (structured.length >= MAX_STRUCTURED) break;
    const text = (script.textContent || '').trim();
    if (text) structured.push(text.slice(0, MAX_STRUCTURED_TEXT));
  }

  const challenge = Boolean(document.querySelector(
    'input[type="password"], iframe[src*="captcha"], [class*="captcha"], [id*="captcha"]'
  ));

  let fallbackText = '';
  if (!blocks.length) {
    const root = document.querySelector('article') ||
      document.querySelector('main') ||
      document.querySelector('[role="main"]') ||
      document.body;
    fallbackText = capped(root ? root.innerText : '', 20000);
  }

  return JSON.stringify({
    meta, blocks, structured, challenge, totalBlocks: total, fallbackText
  });
})()
''';
}
