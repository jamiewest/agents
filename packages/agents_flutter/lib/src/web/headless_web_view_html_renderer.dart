import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'web_page_html_renderer.dart';

/// A [WebPageHtmlRenderer] backed by a hidden platform WebView.
///
/// The page loads in a WebView that is never attached to the widget tree,
/// so its JavaScript runs exactly as in a real browser; the live DOM is
/// then serialized back to HTML. Snapshots are polled rather than taken on
/// the load event because script-built pages keep mutating the document
/// afterwards — Google even navigates to a second URL before showing
/// results — and a mid-navigation poll simply fails and is retried.
///
/// Renders run one at a time: concurrent [render] calls queue, so
/// simultaneous searches cannot stack up WebViews. Each render uses a
/// fresh incognito WebView, disposed when the render completes. Check
/// [isSupported] before constructing; it matches
/// `HeadlessWebViewPageLoader`'s platform set.
class HeadlessWebViewHtmlRenderer implements WebPageHtmlRenderer {
  /// Creates a renderer that polls every [pollInterval] and gives a page
  /// up to [timeout] to produce an accepted snapshot.
  HeadlessWebViewHtmlRenderer({
    this.timeout = const Duration(seconds: 12),
    this.pollInterval = const Duration(milliseconds: 400),
  });

  /// The time budget per page before the last snapshot is returned as-is.
  final Duration timeout;

  /// How long to wait between document snapshots.
  final Duration pollInterval;

  /// Whether the current platform has a headless WebView implementation
  /// (Android, iOS, macOS, Windows; never Flutter web).
  static bool get isSupported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  Future<void> _previousRender = Future.value();

  @override
  Future<RenderedWebPage> render(
    Uri url, {
    String? userAgent,
    bool Function(RenderedWebPage page)? isReady,
  }) {
    final render = _previousRender.then(
      (_) => _render(url, userAgent: userAgent, isReady: isReady),
    );
    _previousRender = render.then((_) {}, onError: (_) {});
    return render;
  }

  Future<RenderedWebPage> _render(
    Uri url, {
    required String? userAgent,
    required bool Function(RenderedWebPage page)? isReady,
  }) async {
    InAppWebViewController? controller;
    final webView = HeadlessInAppWebView(
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
        supportMultipleWindows: false,
        geolocationEnabled: false,
        saveFormData: false,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: false,
        supportZoom: false,
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (created) => controller = created,
    );
    try {
      await webView.run();
      final deadline = DateTime.now().add(timeout);
      RenderedWebPage page = (html: '', url: url);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(pollInterval);
        final snapshot = await _snapshot(controller, url);
        if (snapshot == null) continue;
        page = snapshot;
        if (isReady?.call(snapshot) ?? snapshot.html.isNotEmpty) break;
      }
      return page;
    } finally {
      try {
        await controller?.stopLoading();
      } catch (_) {
        // Best-effort shutdown; disposal below owns final cleanup.
      }
      try {
        await webView.dispose();
      } catch (_) {
        // The native view was already stopped; do not replace the render
        // result with a platform cleanup error.
      }
    }
  }

  /// The current document and address, or `null` when the page is
  /// mid-navigation and cannot be queried yet.
  Future<RenderedWebPage?> _snapshot(
    InAppWebViewController? controller,
    Uri requested,
  ) async {
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (raw is! String) return null;
      final current = Uri.tryParse((await controller.getUrl()).toString());
      return (
        html: raw,
        url: (current?.hasScheme ?? false) ? current! : requested,
      );
    } catch (_) {
      return null;
    }
  }
}
