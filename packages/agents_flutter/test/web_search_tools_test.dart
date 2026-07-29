import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublicWebNavigationPolicy', () {
    test('allows public HTTP and HTTPS addresses', () async {
      final policy = PublicWebNavigationPolicy(
        hostResolver: (_) async => <String>['93.184.216.34'],
      );

      expect(
        (await policy.evaluate(Uri.parse('https://example.com/page'))).allowed,
        isTrue,
      );
      expect(
        (await policy.evaluate(Uri.parse('http://example.com'))).allowed,
        isTrue,
      );
    });

    test('blocks unsafe schemes, credentials, and local names', () async {
      final policy = PublicWebNavigationPolicy(
        hostResolver: (_) async => <String>['93.184.216.34'],
      );

      for (final url in <String>[
        'file:///tmp/secret',
        'https://user:password@example.com',
        'https://localhost',
        'https://service.local',
      ]) {
        expect(
          (await policy.evaluate(Uri.parse(url))).allowed,
          isFalse,
          reason: url,
        );
      }
    });

    test('blocks private and non-public resolved addresses', () async {
      for (final address in <String>[
        '0.0.0.0',
        '10.0.0.1',
        '100.64.0.1',
        '127.0.0.1',
        '169.254.1.1',
        '172.16.0.1',
        '192.0.0.1',
        '192.0.2.1',
        '192.168.1.1',
        '198.51.100.1',
        '203.0.113.1',
        '224.0.0.1',
        '::',
        '::1',
        'fc00::1',
        'fe80::1',
        'ff02::1',
      ]) {
        final policy = PublicWebNavigationPolicy(
          hostResolver: (_) async => <String>[address],
        );
        expect(
          (await policy.evaluate(Uri.parse('https://example.test'))).allowed,
          isFalse,
          reason: address,
        );
      }
    });

    test('blocks a hostname if any resolved address is private', () async {
      final policy = PublicWebNavigationPolicy(
        hostResolver: (_) async => <String>['93.184.216.34', '192.168.1.10'],
      );

      final decision = await policy.evaluate(
        Uri.parse('https://mixed.example'),
      );

      expect(decision.allowed, isFalse);
    });

    test('reports DNS failures as blocked decisions', () async {
      final policy = PublicWebNavigationPolicy(
        hostResolver: (_) => Future<List<String>>.error(Exception('dns')),
      );

      final decision = await policy.evaluate(Uri.parse('https://missing.test'));

      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('resolved'));
    });

    test('honors a custom navigation policy', () async {
      final policy = _AllowAllNavigationPolicy();

      final decision = await policy.evaluate(
        Uri.parse('http://127.0.0.1:8080'),
      );

      expect(decision.allowed, isTrue);
    });
  });

  group('createWebSearchTools', () {
    test('opens an arbitrary direct URL without a prior search', () async {
      final loader = _FakePageLoader();
      final tools = createWebSearchTools(pageLoader: loader);
      final open = tools.first;

      final result =
          await open.invoke(
                AIFunctionArguments(<String, Object?>{
                  'url': 'example.com/article',
                }),
              )
              as Map<String, Object?>;

      expect(loader.urls.single, Uri.parse('https://example.com/article'));
      expect(result['status'], 'success');
      expect(result['text'], 'Readable page');
    });

    test('normalizes protocol-relative and host-port URLs to HTTPS', () {
      expect(
        normalizeWebUrl('//example.com/article'),
        Uri.parse('https://example.com/article'),
      );
      expect(
        normalizeWebUrl('example.com:8443/article'),
        Uri.parse('https://example.com:8443/article'),
      );
      expect(
        normalizeWebUrl('ftp://example.com/archive'),
        Uri.parse('ftp://example.com/archive'),
      );
    });

    test('forwards cancellation to the page loader', () async {
      final loader = _FakePageLoader();
      final tools = createWebSearchTools(pageLoader: loader);
      final source = CancellationTokenSource();

      await tools.first.invoke(
        AIFunctionArguments(<String, Object?>{'url': 'https://example.com'}),
        cancellationToken: source.token,
      );

      expect(loader.cancellationToken, source.token);
      source.dispose();
    });

    test('returns invalid_argument without calling the loader', () async {
      final loader = _FakePageLoader();
      final open = createWebSearchTools(pageLoader: loader).first;

      final result =
          await open.invoke(
                AIFunctionArguments(<String, Object?>{'url': '://bad'}),
              )
              as Map<String, Object?>;

      expect(result['status'], 'invalid_argument');
      expect(loader.urls, isEmpty);
    });

    test('searches, clamps limits, and drops malformed results', () async {
      final source = _FakeSearchSource(<WebSearchResult>[
        const WebSearchResult(title: 'Bad', url: 'file:///tmp/private'),
        const WebSearchResult(
          title: 'One',
          url: 'https://example.com/one',
          snippet: 'First',
        ),
        const WebSearchResult(
          title: 'Two',
          url: 'http://example.com/two',
          snippet: 'Second',
        ),
      ]);
      final tools = createWebSearchTools(
        searchSource: source,
        pageLoader: _FakePageLoader(),
        options: WebSearchToolOptions(defaultMaxResults: 2, maxResultsLimit: 2),
      );
      final search = tools.first;

      final result =
          await search.invoke(
                AIFunctionArguments(<String, Object?>{
                  'query': '  dart agents  ',
                  'maxResults': 99,
                }),
              )
              as Map<String, Object?>;
      final results = result['results']! as List<Map<String, Object?>>;

      expect(source.query, 'dart agents');
      expect(source.maxResults, 2);
      expect(result['discardedResults'], 1);
      expect(results, hasLength(2));
      expect(results.first['url'], 'https://example.com/one');
    });

    test('source-only configuration creates all four tools', () {
      final tools = createWebSearchTools(
        searchSource: _FakeSearchSource(const <WebSearchResult>[]),
      );

      expect(tools.map((tool) => tool.name), <String>[
        webSearchToolName,
        openWebPageToolName,
        expandPageToolName,
        findInPageToolName,
      ]);
    });

    test('categorized sources add a category enum to the schema', () {
      final search = createWebSearchTools(
        searchSource: _FakeSearchSource(const <WebSearchResult>[]),
        categorizedSearchSources: <String, WebSearchSource>{
          'finance': _FakeSearchSource(const <WebSearchResult>[]),
          'technology': _FakeSearchSource(const <WebSearchResult>[]),
        },
      ).first;

      final properties =
          search.parametersSchema!['properties']! as Map<String, Object?>;
      final category = properties['category']! as Map<String, Object?>;
      expect(category['enum'], <String>['finance', 'technology']);
      expect(search.parametersSchema!['required'], <String>['query']);
      expect(search.description, contains('finance, technology'));
    });

    test('without categories the schema carries no category property', () {
      final search = createWebSearchTools(
        searchSource: _FakeSearchSource(const <WebSearchResult>[]),
      ).first;

      final properties =
          search.parametersSchema!['properties']! as Map<String, Object?>;
      expect(properties.containsKey('category'), isFalse);
    });

    test('routes a category to its source, case-insensitively', () async {
      final general = _FakeSearchSource(const <WebSearchResult>[]);
      final finance = _FakeSearchSource(const <WebSearchResult>[
        WebSearchResult(title: 'Rates', url: 'https://finance.example.com/'),
      ]);
      final search = createWebSearchTools(
        searchSource: general,
        categorizedSearchSources: <String, WebSearchSource>{'finance': finance},
      ).first;

      final result =
          await search.invoke(
                AIFunctionArguments(<String, Object?>{
                  'query': 'bond yields',
                  'category': 'Finance',
                }),
              )
              as Map<String, Object?>;

      expect(finance.query, 'bond yields');
      expect(general.query, isNull);
      expect(result['category'], 'finance');
    });

    test('an unknown category falls back to the default with a note', () async {
      final general = _FakeSearchSource(const <WebSearchResult>[]);
      final search = createWebSearchTools(
        searchSource: general,
        categorizedSearchSources: <String, WebSearchSource>{
          'finance': _FakeSearchSource(const <WebSearchResult>[]),
        },
      ).first;

      final result =
          await search.invoke(
                AIFunctionArguments(<String, Object?>{
                  'query': 'anything',
                  'category': 'sports',
                }),
              )
              as Map<String, Object?>;

      expect(general.query, 'anything');
      expect(result['status'], 'success');
      expect(result['note'], contains('sports'));
    });

    test('categories without a default source require the parameter', () async {
      final search = createWebSearchTools(
        categorizedSearchSources: <String, WebSearchSource>{
          'finance': _FakeSearchSource(const <WebSearchResult>[]),
        },
      ).first;

      expect(search.parametersSchema!['required'], <String>[
        'query',
        'category',
      ]);

      final result =
          await search.invoke(
                AIFunctionArguments(<String, Object?>{
                  'query': 'anything',
                  'category': 'sports',
                }),
              )
              as Map<String, Object?>;
      expect(result['status'], 'invalid_argument');
      expect(result['message'], contains('finance'));
    });

    test('page-loader-only configuration omits only the search tool', () {
      final tools = createWebSearchTools(pageLoader: _FakePageLoader());

      expect(tools.map((tool) => tool.name), <String>[
        openWebPageToolName,
        expandPageToolName,
        findInPageToolName,
      ]);
    });

    test('an objective focuses open_web_page on matching blocks', () async {
      final tools = createWebSearchTools(pageLoader: _FakeBlockPageLoader());

      final opened =
          await tools.first.invoke(
                AIFunctionArguments(<String, Object?>{
                  'url': 'https://example.gov/guide',
                  'objective': 'fees for electronic copies',
                }),
              )
              as Map<String, Object?>;

      expect(opened['pageId'], 'page-1');
      final content = opened['content']! as String;
      expect(content, contains('Focused on: fees for electronic copies'));
      expect(content, contains('### Fees'));
      expect(content, contains('Electronic copies are twenty-five dollars.'));
      expect(content, contains('[…]'));
      expect(content, isNot(contains('Intro paragraph.')));
      expect(opened.containsKey('note'), isFalse);
    });

    test(
      'an unmatched objective falls back to lead content with a note',
      () async {
        final tools = createWebSearchTools(pageLoader: _FakeBlockPageLoader());

        final opened =
            await tools.first.invoke(
                  AIFunctionArguments(<String, Object?>{
                    'url': 'https://example.gov/guide',
                    'objective': 'quantum chromodynamics',
                  }),
                )
                as Map<String, Object?>;

        expect(opened['note'], contains('Nothing matched'));
        expect(opened['content'], contains('Intro paragraph.'));
      },
    );

    test('find_in_page ranks cached blocks for a new question', () async {
      final tools = createWebSearchTools(pageLoader: _FakeBlockPageLoader());
      final find = tools.singleWhere((tool) => tool.name == findInPageToolName);
      await tools.first.invoke(
        AIFunctionArguments(<String, Object?>{
          'url': 'https://example.gov/guide',
        }),
      );

      final found =
          await find.invoke(
                AIFunctionArguments(<String, Object?>{
                  'pageId': 'page-1',
                  'query': 'electronic copies',
                }),
              )
              as Map<String, Object?>;
      expect(found['status'], 'success');
      expect(found['blocks'], contains('b3'));
      expect(
        found['content'],
        contains('Electronic copies are twenty-five dollars.'),
      );

      final unmatched =
          await find.invoke(
                AIFunctionArguments(<String, Object?>{
                  'pageId': 'page-1',
                  'query': 'zebra migration',
                }),
              )
              as Map<String, Object?>;
      expect(unmatched['status'], 'no_matches');
      expect(unmatched['outline'], isNotEmpty);

      final expired =
          await find.invoke(
                AIFunctionArguments(<String, Object?>{
                  'pageId': 'page-9',
                  'query': 'anything',
                }),
              )
              as Map<String, Object?>;
      expect(expired['status'], 'not_found');
    });

    test('open_web_page returns a pageId that expand_page resolves', () async {
      final tools = createWebSearchTools(pageLoader: _FakeBlockPageLoader());
      final open = tools.first;
      final expand = tools.singleWhere(
        (tool) => tool.name == expandPageToolName,
      );

      final opened =
          await open.invoke(
                AIFunctionArguments(<String, Object?>{
                  'url': 'https://example.gov/guide',
                }),
              )
              as Map<String, Object?>;
      expect(opened['pageId'], 'page-1');
      expect(opened['content'], contains('# Fixture'));

      final expanded =
          await expand.invoke(
                AIFunctionArguments(<String, Object?>{
                  'pageId': 'page-1',
                  'blockIds': <Object?>['b3'],
                }),
              )
              as Map<String, Object?>;
      expect(expanded['status'], 'success');
      expect(expanded['blocks'], <String>['b3']);
      expect(
        expanded['content'],
        contains('Electronic copies are twenty-five dollars.'),
      );
      expect(expanded['content'], contains('Under: Guide > Fees'));
    });

    test('expand_page expands a whole section by heading', () async {
      final tools = createWebSearchTools(pageLoader: _FakeBlockPageLoader());
      await tools.first.invoke(
        AIFunctionArguments(<String, Object?>{
          'url': 'https://example.gov/guide',
        }),
      );

      final expanded =
          await tools
                  .singleWhere((tool) => tool.name == expandPageToolName)
                  .invoke(
                    AIFunctionArguments(<String, Object?>{
                      'pageId': 'page-1',
                      'heading': 'fees',
                    }),
                  )
              as Map<String, Object?>;
      expect(expanded['status'], 'success');
      expect(expanded['blocks'], <String>['b2', 'b3']);
      expect(expanded['content'], contains('### Fees'));
    });

    test('expand_page reports expired and malformed requests', () async {
      final tools = createWebSearchTools(pageLoader: _FakeBlockPageLoader());
      final expand = tools.singleWhere(
        (tool) => tool.name == expandPageToolName,
      );

      final missing =
          await expand.invoke(
                AIFunctionArguments(<String, Object?>{'pageId': 'page-9'}),
              )
              as Map<String, Object?>;
      expect(missing['status'], 'not_found');
      expect(missing['message'], contains('open_web_page'));

      await tools.first.invoke(
        AIFunctionArguments(<String, Object?>{
          'url': 'https://example.gov/guide',
        }),
      );
      final selectorless =
          await expand.invoke(
                AIFunctionArguments(<String, Object?>{'pageId': 'page-1'}),
              )
              as Map<String, Object?>;
      expect(selectorless['status'], 'invalid_argument');
      expect(selectorless['outline'], contains('# Guide [b0-b3]'));

      final unknownBlocks =
          await expand.invoke(
                AIFunctionArguments(<String, Object?>{
                  'pageId': 'page-1',
                  'blockIds': <Object?>['b99'],
                }),
              )
              as Map<String, Object?>;
      expect(unknownBlocks['status'], 'invalid_argument');
      expect(unknownBlocks['message'], contains('b0-b3'));

      final wrongHeading =
          await expand.invoke(
                AIFunctionArguments(<String, Object?>{
                  'pageId': 'page-1',
                  'heading': 'Pricing',
                }),
              )
              as Map<String, Object?>;
      expect(wrongHeading['status'], 'invalid_argument');
      expect(wrongHeading['message'], contains('Pricing'));
    });

    test('the page cache honors maxCachedPages', () async {
      final tools = createWebSearchTools(
        pageLoader: _FakeBlockPageLoader(),
        options: WebSearchToolOptions(maxCachedPages: 1),
      );
      await tools.first.invoke(
        AIFunctionArguments(<String, Object?>{'url': 'https://a.example.com'}),
      );
      await tools.first.invoke(
        AIFunctionArguments(<String, Object?>{'url': 'https://b.example.com'}),
      );

      final evicted =
          await tools
                  .singleWhere((tool) => tool.name == expandPageToolName)
                  .invoke(
                    AIFunctionArguments(<String, Object?>{
                      'pageId': 'page-1',
                      'blockIds': <Object?>['b0'],
                    }),
                  )
              as Map<String, Object?>;
      expect(evicted['status'], 'not_found');

      final kept =
          await tools
                  .singleWhere((tool) => tool.name == expandPageToolName)
                  .invoke(
                    AIFunctionArguments(<String, Object?>{
                      'pageId': 'page-2',
                      'blockIds': <Object?>['b0'],
                    }),
                  )
              as Map<String, Object?>;
      expect(kept['status'], 'success');
    });

    test('loads without blocks return no pageId', () async {
      final tools = createWebSearchTools(pageLoader: _FakePageLoader());

      final opened =
          await tools.first.invoke(
                AIFunctionArguments(<String, Object?>{
                  'url': 'https://example.com',
                }),
              )
              as Map<String, Object?>;

      expect(opened.containsKey('pageId'), isFalse);
    });

    test('validates option bounds', () {
      expect(
        () => createWebSearchTools(
          pageLoader: _FakePageLoader(),
          options: WebSearchToolOptions(
            defaultMaxResults: 3,
            maxResultsLimit: 2,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => HeadlessWebViewPageLoader(
          options: WebSearchToolOptions(maxPageCharacters: 0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('WebPageContent', () {
    test('serializes metadata and structured failures', () {
      final success = WebPageContent(
        status: WebPageLoadStatus.success,
        requestedUrl: Uri.parse('https://example.com'),
        finalUrl: Uri.parse('https://example.com/final'),
        title: 'Example',
        canonicalUrl: Uri.parse('https://example.com/canonical'),
        description: 'Description',
        text: 'Body',
        truncated: true,
      ).toJson();
      final blocked = WebPageContent(
        status: WebPageLoadStatus.blocked,
        requestedUrl: Uri.parse('https://localhost'),
        message: 'Blocked.',
      ).toJson();

      expect(success['status'], 'success');
      expect(success['url'], 'https://example.com/final');
      expect(success['truncated'], isTrue);
      expect(blocked['status'], 'blocked');
      expect(blocked['message'], 'Blocked.');
    });
  });
}

final class _FakeSearchSource implements WebSearchSource {
  _FakeSearchSource(this.results);

  final Iterable<WebSearchResult> results;
  String? query;
  int? maxResults;

  @override
  Future<Iterable<WebSearchResult>> search(
    String query, {
    required int maxResults,
    CancellationToken? cancellationToken,
  }) async {
    this.query = query;
    this.maxResults = maxResults;
    return results;
  }
}

/// Serves a fixed block-structured page for any URL, like a Phase 1
/// extraction would produce.
final class _FakeBlockPageLoader implements WebPageLoader {
  @override
  Future<WebPageContent> load(
    Uri url, {
    CancellationToken? cancellationToken,
  }) async {
    final extraction = WebPageExtraction.parse(<String, Object?>{
      'meta': <String, Object?>{'title': 'Fixture'},
      'blocks': <Object?>[
        <String, Object?>{
          'kind': 'heading',
          'level': 1,
          'text': 'Guide',
          'container': 'main',
        },
        <String, Object?>{
          'kind': 'paragraph',
          'text': 'Intro paragraph.',
          'container': 'main',
        },
        <String, Object?>{
          'kind': 'heading',
          'level': 2,
          'text': 'Fees',
          'container': 'main',
        },
        <String, Object?>{
          'kind': 'paragraph',
          'text': 'Electronic copies are twenty-five dollars.',
          'container': 'main',
        },
      ],
    });
    final rendered = renderWebPageMarkdown(
      extraction: extraction,
      sourceUrl: url,
      maxCharacters: 20000,
    );
    return WebPageContent(
      status: WebPageLoadStatus.success,
      requestedUrl: url,
      finalUrl: url,
      title: extraction.title,
      text: extraction.plainText,
      blocks: extraction.blocks,
      outline: extraction.outline,
      contentMarkdown: rendered.markdown,
    );
  }
}

final class _FakePageLoader implements WebPageLoader {
  final List<Uri> urls = <Uri>[];
  CancellationToken? cancellationToken;

  @override
  Future<WebPageContent> load(
    Uri url, {
    CancellationToken? cancellationToken,
  }) async {
    urls.add(url);
    this.cancellationToken = cancellationToken;
    return WebPageContent(
      status: WebPageLoadStatus.success,
      requestedUrl: url,
      finalUrl: url,
      title: 'Page',
      text: 'Readable page',
    );
  }
}

final class _AllowAllNavigationPolicy implements WebNavigationPolicy {
  @override
  Future<WebNavigationDecision> evaluate(Uri url) async =>
      const WebNavigationDecision.allow();
}
