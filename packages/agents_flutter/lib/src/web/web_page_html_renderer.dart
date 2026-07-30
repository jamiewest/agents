/// A page snapshot from a [WebPageHtmlRenderer]: the document HTML and the
/// URL it was served from, which redirects can move off the requested one.
typedef RenderedWebPage = ({String html, Uri url});

/// Renders a web page in a browser engine and returns its HTML after the
/// page's own JavaScript has run.
///
/// Script-built pages keep mutating the document after the load event —
/// some, like google.com, even navigate again before showing results — so
/// implementations take successive snapshots and complete with the first
/// one [isReady] accepts, or the last one taken when their time budget
/// runs out. A `null` [isReady] accepts the first non-empty document.
///
/// Distinct from `WebPageLoader`, which loads a page into *extracted,
/// structured evidence* for the reading tools; this interface returns raw
/// HTML for clients that parse it themselves (like
/// `SearchUrlWebSearchSource` rendering a script-built results page).
abstract interface class WebPageHtmlRenderer {
  /// Loads [url], sending [userAgent] when given, and returns the
  /// document once [isReady] accepts a snapshot or time runs out.
  Future<RenderedWebPage> render(
    Uri url, {
    String? userAgent,
    bool Function(RenderedWebPage page)? isReady,
  });
}
