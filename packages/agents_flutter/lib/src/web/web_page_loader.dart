import 'package:extensions/system.dart';

import 'web_content_block.dart';

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
///
/// Successful loads carry the structured evidence pipeline's output —
/// typed [blocks] with heading paths, the heading [outline],
/// [structuredData], and pre-rendered [contentMarkdown] — alongside the
/// original flat [text], which remains the fallback when block extraction
/// yields nothing.
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
    this.blocks = const <WebContentBlock>[],
    this.outline = const <WebPageOutlineSection>[],
    this.structuredData = const <WebStructuredData>[],
    this.siteName,
    this.publishedTime,
    this.modifiedTime,
    this.author,
    this.contentMarkdown,
    this.omittedBlocks = 0,
    this.scriptOmittedBlocks = 0,
    this.boilerplateBlocks = 0,
    this.duplicateBlocks = 0,
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

  /// The extracted semantic blocks, in source order.
  final List<WebContentBlock> blocks;

  /// The heading outline over the non-boilerplate blocks.
  final List<WebPageOutlineSection> outline;

  /// Machine-readable data found on the page, labeled by origin.
  final List<WebStructuredData> structuredData;

  /// The publishing site's name, when declared.
  final String? siteName;

  /// The declared publication time, verbatim as found.
  final String? publishedTime;

  /// The declared modification time, verbatim as found.
  final String? modifiedTime;

  /// The declared author, when present.
  final String? author;

  /// The evidence markdown rendered from [blocks] under the configured
  /// character budget, or `null` when no blocks were extracted.
  final String? contentMarkdown;

  /// Blocks not represented in [contentMarkdown]: dropped by the
  /// in-script cap or by the character budget. Reported, never silent.
  final int omittedBlocks;

  /// The subset of [omittedBlocks] dropped by the in-script extraction
  /// cap, kept separate so query-focused re-renders can rebuild an honest
  /// total after replacing the budget-based part.
  final int scriptOmittedBlocks;

  /// Blocks suppressed as navigation/header/footer/aside chrome.
  final int boilerplateBlocks;

  /// Blocks marked as verbatim repeats of earlier ones; skipped in the
  /// markdown and never counted as independent confirmation.
  final int duplicateBlocks;

  /// Converts this result to model-consumable JSON.
  ///
  /// With blocks, the package carries `content` markdown plus the
  /// `outline`; without them, the flat `text` field as before.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'requestedUrl': requestedUrl.toString(),
    if (finalUrl != null) 'url': finalUrl.toString(),
    if (title != null && title!.isNotEmpty) 'title': title,
    if (canonicalUrl != null) 'canonicalUrl': canonicalUrl.toString(),
    if (description != null && description!.isNotEmpty)
      'description': description,
    if (siteName != null) 'siteName': siteName,
    if (publishedTime != null) 'published': publishedTime,
    if (modifiedTime != null) 'modified': modifiedTime,
    if (author != null) 'author': author,
    if (contentMarkdown case final content? when content.isNotEmpty)
      'content': content
    else if (text.isNotEmpty)
      'text': text,
    if (outline.isNotEmpty)
      'outline': <String>[for (final section in outline) section.describe()],
    if (structuredData.isNotEmpty)
      'structuredData': <Object?>[
        for (final entry in structuredData) entry.toJson(),
      ],
    if (omittedBlocks > 0) 'omittedBlocks': omittedBlocks,
    if (boilerplateBlocks > 0) 'suppressedBoilerplateBlocks': boilerplateBlocks,
    if (duplicateBlocks > 0) 'duplicateBlocks': duplicateBlocks,
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
