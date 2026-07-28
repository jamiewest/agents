import 'package:extensions/system.dart';

/// Discovers public web pages for an agent search query.
///
/// Hosts provide the implementation and own any API credentials it uses.
abstract interface class WebSearchSource {
  /// Returns up to [maxResults] results for [query].
  Future<Iterable<WebSearchResult>> search(
    String query, {
    required int maxResults,
    CancellationToken? cancellationToken,
  });
}

/// A single result returned by a [WebSearchSource].
class WebSearchResult {
  /// Creates a web search result.
  const WebSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  /// Human-readable result title.
  final String title;

  /// Absolute HTTP or HTTPS destination URL.
  final String url;

  /// Short result summary supplied by the search backend.
  final String snippet;

  /// Converts this result to model-consumable JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'url': url,
    'snippet': snippet,
  };
}
