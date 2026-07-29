import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

WebPageContent _page(String url) => WebPageContent(
  status: WebPageLoadStatus.success,
  requestedUrl: Uri.parse(url),
  finalUrl: Uri.parse(url),
  text: 'content of $url',
);

void main() {
  test('assigns sequential ids and finds stored pages', () {
    final store = WebPageSessionStore();

    final first = store.store(_page('https://a.example.com/'));
    final second = store.store(_page('https://b.example.com/'));

    expect(first, 'page-1');
    expect(second, 'page-2');
    expect(store.find('page-1')?.url, Uri.parse('https://a.example.com/'));
    expect(store.find('page-2')?.content.text, contains('b.example.com'));
    expect(store.find('page-9'), isNull);
  });

  test('evicts the least recently used page at capacity', () {
    final store = WebPageSessionStore(maxPages: 2);

    store.store(_page('https://a.example.com/'));
    store.store(_page('https://b.example.com/'));
    // Touch page-1 so page-2 becomes the least recently used.
    store.find('page-1');
    store.store(_page('https://c.example.com/'));

    expect(store.find('page-1'), isNotNull);
    expect(store.find('page-2'), isNull);
    expect(store.find('page-3'), isNotNull);
  });

  test('reopening a URL replaces the earlier entry', () {
    final store = WebPageSessionStore(maxPages: 3);

    store.store(_page('https://a.example.com/'));
    final replacement = store.store(_page('https://a.example.com/'));

    expect(replacement, 'page-2');
    expect(store.find('page-1'), isNull, reason: 'old id expires');
    expect(store.find('page-2'), isNotNull);
  });

  test('rejects a non-positive capacity', () {
    expect(() => WebPageSessionStore(maxPages: 0), throwsArgumentError);
  });
}
