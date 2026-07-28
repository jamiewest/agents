import 'dart:async';
import 'dart:convert';

import 'package:extensions/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'web_navigation_policy.dart';
import 'web_page_loader.dart';
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
  }) : _navigationPolicy = navigationPolicy ?? PublicWebNavigationPolicy(),
       _options = options ?? WebSearchToolOptions() {
    _options.validate();
  }

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
    final rawText = (extracted['text'] as String? ?? '').trim();
    final truncated = rawText.length > _options.maxPageCharacters;
    final text = truncated
        ? rawText.substring(0, _options.maxPageCharacters)
        : rawText;
    final challenge = extracted['challenge'] == true;
    final status = challenge
        ? WebPageLoadStatus.challengeDetected
        : text.isEmpty
        ? WebPageLoadStatus.emptyContent
        : WebPageLoadStatus.success;

    return WebPageContent(
      status: status,
      requestedUrl: requestedUrl,
      finalUrl: finalUrl,
      title: _nonEmpty(extracted['title']),
      canonicalUrl: _tryParseUri(_nonEmpty(extracted['canonicalUrl'])),
      description: _nonEmpty(extracted['description']),
      text: text,
      truncated: truncated,
      message: challenge
          ? 'The page appears to require login, consent, CAPTCHA, or human verification.'
          : text.isEmpty
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

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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

  static const String _extractionScript = r'''
(() => {
  const clean = (value) => (value || '').replace(/\r/g, '').trim();
  const root =
    document.querySelector('article') ||
    document.querySelector('main') ||
    document.querySelector('[role="main"]') ||
    document.body;
  const text = clean(root ? root.innerText : '');
  const title = clean(document.title);
  const canonical = document.querySelector('link[rel~="canonical"]');
  const description =
    document.querySelector('meta[name="description"]') ||
    document.querySelector('meta[property="og:description"]');
  const challengeText = `${title}\n${text.slice(0, 5000)}`.toLowerCase();
  const challenge =
    Boolean(document.querySelector(
      'input[type="password"], iframe[src*="captcha"], [class*="captcha"], [id*="captcha"]'
    )) ||
    challengeText.includes('verify you are human') ||
    challengeText.includes('checking your browser') ||
    challengeText.includes('unusual traffic') ||
    challengeText.includes('access denied') ||
    challengeText.includes('consent required');

  return JSON.stringify({
    title,
    canonicalUrl: canonical ? canonical.href : '',
    description: description ? description.content : '',
    text,
    challenge
  });
})()
''';
}
