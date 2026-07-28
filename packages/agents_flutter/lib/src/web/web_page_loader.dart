import 'package:extensions/system.dart';

/// Outcome categories returned by [WebPageLoader].
enum WebPageLoadStatus {
  /// The page loaded and readable text was extracted.
  success,

  /// Navigation was refused by the configured policy.
  blocked,

  /// The page did not finish loading before the configured deadline.
  timeout,

  /// The main document returned an unsuccessful HTTP status.
  httpError,

  /// The browser failed to load or inspect the page.
  loadError,

  /// The page loaded but contained no readable text.
  emptyContent,

  /// The page appears to require login, consent, CAPTCHA, or verification.
  challengeDetected,

  /// The loader is unavailable on the current platform.
  unsupported,
}

/// Extracted content and metadata for one web page load.
class WebPageContent {
  /// Creates a page-load result.
  const WebPageContent({
    required this.status,
    required this.requestedUrl,
    this.finalUrl,
    this.title,
    this.canonicalUrl,
    this.description,
    this.text = '',
    this.truncated = false,
    this.httpStatusCode,
    this.message,
  });

  /// High-level outcome of the page load.
  final WebPageLoadStatus status;

  /// URL supplied to the loader.
  final Uri requestedUrl;

  /// URL after redirects, when known.
  final Uri? finalUrl;

  /// Document title, when available.
  final String? title;

  /// Page-declared canonical URL, when available.
  final Uri? canonicalUrl;

  /// Page metadata description, when available.
  final String? description;

  /// Visible, readable page text.
  final String text;

  /// Whether [text] was capped by the configured character limit.
  final bool truncated;

  /// Main-document HTTP status when an HTTP error was observed.
  final int? httpStatusCode;

  /// Safe diagnostic intended for the model.
  final String? message;

  /// Converts this result to model-consumable JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'requestedUrl': requestedUrl.toString(),
    if (finalUrl != null) 'url': finalUrl.toString(),
    if (title != null && title!.isNotEmpty) 'title': title,
    if (canonicalUrl != null) 'canonicalUrl': canonicalUrl.toString(),
    if (description != null && description!.isNotEmpty)
      'description': description,
    if (text.isNotEmpty) 'text': text,
    'truncated': truncated,
    if (httpStatusCode != null) 'httpStatusCode': httpStatusCode,
    if (message != null && message!.isNotEmpty) 'message': message,
  };
}

/// Loads a page and extracts model-consumable content from it.
abstract interface class WebPageLoader {
  /// Loads [url], honoring [cancellationToken] when supplied.
  Future<WebPageContent> load(Uri url, {CancellationToken? cancellationToken});
}
