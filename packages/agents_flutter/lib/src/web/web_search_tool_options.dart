/// Configuration for local web search and page-opening tools.
class WebSearchToolOptions {
  /// Creates web tool options.
  WebSearchToolOptions({
    this.defaultMaxResults = 5,
    this.maxResultsLimit = 10,
    this.pageLoadTimeout = const Duration(seconds: 20),
    this.domSettleDelay = const Duration(milliseconds: 500),
    this.maxPageCharacters = 20000,
    this.maxCachedPages = 8,
  });

  /// Result count used when the model omits `maxResults`.
  int defaultMaxResults;

  /// Largest result count accepted from the model.
  int maxResultsLimit;

  /// Maximum time allowed for a page load.
  Duration pageLoadTimeout;

  /// Delay after load completion before extracting dynamic DOM content.
  Duration domSettleDelay;

  /// Maximum number of page-text characters returned to the model.
  int maxPageCharacters;

  /// Opened pages kept for `expand_page` before the least recently used
  /// is dropped. Block texts are already capped in-script, so this bounds
  /// the cache's memory alongside those caps.
  int maxCachedPages;

  /// Throws when any option is outside its supported range.
  void validate() {
    if (defaultMaxResults < 1 ||
        maxResultsLimit < 1 ||
        defaultMaxResults > maxResultsLimit) {
      throw ArgumentError(
        'defaultMaxResults must be between 1 and maxResultsLimit.',
      );
    }
    if (pageLoadTimeout <= Duration.zero) {
      throw ArgumentError.value(
        pageLoadTimeout,
        'pageLoadTimeout',
        'Must be greater than zero.',
      );
    }
    if (domSettleDelay < Duration.zero) {
      throw ArgumentError.value(
        domSettleDelay,
        'domSettleDelay',
        'Must not be negative.',
      );
    }
    if (maxPageCharacters < 1) {
      throw ArgumentError.value(
        maxPageCharacters,
        'maxPageCharacters',
        'Must be greater than zero.',
      );
    }
    if (maxCachedPages < 1) {
      throw ArgumentError.value(
        maxCachedPages,
        'maxCachedPages',
        'Must be greater than zero.',
      );
    }
  }
}
