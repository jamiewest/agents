import 'dart:collection';

import 'web_page_loader.dart';

/// One cached page: its session-stable id and the load's full content.
class StoredWebPage {
  /// Creates a stored page.
  const StoredWebPage({
    required this.id,
    required this.url,
    required this.content,
  });

  /// The session-stable identifier, `page-1`, `page-2`, …
  final String id;

  /// The address the content was extracted from.
  final Uri url;

  /// The load's content, blocks and outline included.
  final WebPageContent content;
}

/// A small LRU cache of opened pages, shared by one web tool set.
///
/// `open_web_page` stores each block-bearing load here and reports the
/// assigned `page-N` id; `expand_page` (and, in Phase 3, `find_in_page`)
/// resolve those ids back to blocks. The store lives exactly as long as
/// its tool set — one agent build for one conversation — so ids never leak
/// across conversations. Reopening a URL replaces its previous entry
/// rather than filling the cache with copies of one page.
class WebPageSessionStore {
  /// Creates a store keeping at most [maxPages] pages.
  WebPageSessionStore({int maxPages = 8}) : _maxPages = maxPages {
    if (maxPages < 1) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be at least 1.');
    }
  }

  final int _maxPages;
  final LinkedHashMap<String, StoredWebPage> _pages =
      LinkedHashMap<String, StoredWebPage>();
  int _nextId = 0;

  /// Stores [content] and returns the page's assigned id.
  ///
  /// The least recently used page is dropped once the cache is full; a
  /// page previously stored for the same URL is replaced (its old id
  /// expires).
  String store(WebPageContent content) {
    final url = content.finalUrl ?? content.requestedUrl;
    _pages.removeWhere((_, page) => page.url == url);
    final id = 'page-${++_nextId}';
    _pages[id] = StoredWebPage(id: id, url: url, content: content);
    while (_pages.length > _maxPages) {
      _pages.remove(_pages.keys.first);
    }
    return id;
  }

  /// The stored page with [pageId], marked most recently used — or `null`
  /// when the id is unknown or already evicted.
  StoredWebPage? find(String pageId) {
    final page = _pages.remove(pageId.trim());
    if (page == null) return null;
    _pages[page.id] = page;
    return page;
  }
}
