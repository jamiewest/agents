import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A raw extraction-script result resembling a small government page:
/// header/nav chrome, an article with nested headings, a fee table, a
/// list, code, and footer boilerplate.
Map<String, Object?> _fixture() => <String, Object?>{
  'meta': <String, Object?>{
    'title': 'Assessor Property Search',
    'canonicalUrl': 'https://example.gov/assessor',
    'description': 'Search parcels and request records.',
    'siteName': 'Example County',
    'published': '',
    'modified': '2026-06-12',
    'author': '',
  },
  'blocks': <Object?>[
    <String, Object?>{
      'kind': 'list',
      'text': '',
      'items': <Object?>['Home', 'Departments', 'Contact'],
      'container': 'nav',
      'path': 'nav>ul',
      'links': <Object?>[
        <String, Object?>{'t': 'Home', 'h': 'https://example.gov/'},
      ],
    },
    <String, Object?>{
      'kind': 'heading',
      'level': 1,
      'text': 'Property Search',
      'container': 'main',
      'path': 'main>h1',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': 'Look up any parcel in the county.',
      'container': 'main',
      'path': 'main>p',
    },
    <String, Object?>{
      'kind': 'heading',
      'level': 2,
      'text': 'Fees',
      'container': 'main',
      'path': 'main>section>h2',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': 'The following charges apply.',
      'container': 'main',
      'path': 'main>section>p',
      'links': <Object?>[
        <String, Object?>{
          't': 'Request form',
          'h': 'https://example.gov/forms/request',
        },
        <String, Object?>{'t': 'skip me', 'h': 'javascript:void(0)'},
      ],
    },
    <String, Object?>{
      'kind': 'table',
      'text': '',
      'table': <String, Object?>{
        'caption': 'Assessment Roll Charges',
        'columns': <Object?>['Format', 'Fee'],
        'rows': <Object?>[
          <Object?>['Electronic', r'$25'],
          <Object?>['Printed', r'$80'],
        ],
      },
      'container': 'main',
      'path': 'main>section>table',
    },
    <String, Object?>{
      'kind': 'heading',
      'level': 2,
      'text': 'How to apply',
      'container': 'main',
      'path': 'main>section:2>h2',
    },
    <String, Object?>{
      'kind': 'code',
      'text': 'curl https://example.gov/api/roll',
      'container': 'main',
      'path': 'main>section:2>pre',
    },
    <String, Object?>{
      'kind': 'heading',
      'level': 3,
      'text': 'Departments',
      'container': 'footer',
      'path': 'footer>h3',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': '© Example County',
      'container': 'footer',
      'path': 'footer>p',
    },
  ],
  'structured': <Object?>[
    '{"@type": "GovernmentOrganization", "name": "Example County", '
        '"publisher": {"name": "Example County Portal"}, '
        '"datePublished": "2026-05-12"}',
  ],
  'challenge': false,
  'totalBlocks': 12,
  'fallbackText': '',
};

void main() {
  group('WebPageExtraction.parse', () {
    test('assigns heading paths from the content hierarchy', () {
      final extraction = WebPageExtraction.parse(_fixture());

      final table = extraction.blocks.singleWhere(
        (block) => block.type == WebContentBlockType.table,
      );
      expect(table.headingPath, <String>['Property Search', 'Fees']);
      expect(table.table?.caption, 'Assessment Roll Charges');
      expect(table.table?.rows.first, <String>['Electronic', r'$25']);

      final code = extraction.blocks.singleWhere(
        (block) => block.type == WebContentBlockType.code,
      );
      expect(code.headingPath, <String>['Property Search', 'How to apply']);
    });

    test('flags nav and footer blocks and keeps them out of paths', () {
      final extraction = WebPageExtraction.parse(_fixture());

      final navList = extraction.blocks.first;
      expect(navList.type, WebContentBlockType.list);
      expect(navList.isBoilerplate, isTrue);

      // The footer h3 must not become an ancestor of anything.
      final footerParagraph = extraction.blocks.last;
      expect(footerParagraph.isBoilerplate, isTrue);
      expect(footerParagraph.headingPath, isNot(contains('Departments')));
    });

    test('builds the outline over content headings with block ranges', () {
      final extraction = WebPageExtraction.parse(_fixture());

      expect(extraction.outline.map((s) => s.heading), <String>[
        'Property Search',
        'Fees',
        'How to apply',
      ]);
      final fees = extraction.outline[1];
      expect(fees.level, 2);
      final feeBlocks = extraction.blocks
          .sublist(fees.firstBlockIndex, fees.lastBlockIndex + 1)
          .map((block) => block.type);
      expect(feeBlocks, contains(WebContentBlockType.table));
      expect(fees.describe(), contains('## Fees'));
    });

    test('drops non-web links and counts script omissions', () {
      final extraction = WebPageExtraction.parse(_fixture());

      final feesIntro = extraction.blocks.singleWhere(
        (block) => block.text == 'The following charges apply.',
      );
      expect(feesIntro.links.map((link) => link.url), <String>[
        'https://example.gov/forms/request',
      ]);
      expect(extraction.omittedBlocks, 2, reason: '12 seen, 10 emitted');
    });

    test('parses JSON-LD and fills metadata gaps from it', () {
      final extraction = WebPageExtraction.parse(_fixture());

      expect(
        extraction.structuredData.single.schemaType,
        'GovernmentOrganization',
      );
      expect(extraction.modified, '2026-06-12', reason: 'meta wins');
      expect(extraction.published, '2026-05-12', reason: 'JSON-LD fallback');
      expect(extraction.siteName, 'Example County');
    });

    test('detects challenges from text phrases', () {
      final raw = _fixture();
      (raw['blocks']! as List).insert(1, <String, Object?>{
        'kind': 'paragraph',
        'text': 'Please verify you are human to continue.',
        'container': 'main',
      });

      expect(WebPageExtraction.parse(raw).challenge, isTrue);
    });

    test('an unrecognized shape yields an empty extraction', () {
      final extraction = WebPageExtraction.parse(<String, Object?>{
        'unexpected': true,
      });

      expect(extraction.blocks, isEmpty);
      expect(extraction.outline, isEmpty);
      expect(extraction.plainText, isEmpty);
      expect(extraction.challenge, isFalse);
    });

    test('falls back to the raw text when no blocks were extracted', () {
      final extraction = WebPageExtraction.parse(<String, Object?>{
        'meta': <String, Object?>{'title': 'Plain'},
        'blocks': const <Object?>[],
        'fallbackText': 'Just some readable text.',
      });

      expect(extraction.plainText, 'Just some readable text.');
    });
  });

  group('renderWebPageMarkdown', () {
    test('renders header facts, hierarchy, tables, and links', () {
      final extraction = WebPageExtraction.parse(_fixture());

      final rendered = renderWebPageMarkdown(
        extraction: extraction,
        sourceUrl: Uri.parse('https://example.gov/assessor/search'),
        maxCharacters: 20000,
      );

      expect(rendered.markdown, contains('# Assessor Property Search'));
      expect(rendered.markdown, contains('Source: example.gov'));
      expect(rendered.markdown, contains('Site: Example County'));
      expect(rendered.markdown, contains('Modified: 2026-06-12'));
      expect(
        rendered.markdown,
        contains('Canonical: https://example.gov/assessor'),
      );
      expect(rendered.markdown, contains('### Fees'));
      expect(rendered.markdown, contains('| Electronic | \$25 |'));
      expect(rendered.markdown, contains('**Assessment Roll Charges**'));
      expect(
        rendered.markdown,
        contains('[Request form](https://example.gov/forms/request)'),
      );
      expect(rendered.markdown, contains('```\ncurl'));
      expect(rendered.markdown, isNot(contains('© Example County')));
      expect(rendered.boilerplateBlocks, 3);
      expect(rendered.omittedForBudget, 0);
    });

    test('stops at the character budget and reports omissions', () {
      final extraction = WebPageExtraction.parse(_fixture());

      final rendered = renderWebPageMarkdown(
        extraction: extraction,
        sourceUrl: Uri.parse('https://example.gov/assessor'),
        maxCharacters: 220,
      );

      expect(rendered.markdown.length, lessThanOrEqualTo(240));
      expect(rendered.omittedForBudget, greaterThan(0));
    });
  });

  group('WebPageContent.toJson', () {
    test('emits the evidence package when blocks exist', () {
      final extraction = WebPageExtraction.parse(_fixture());
      final rendered = renderWebPageMarkdown(
        extraction: extraction,
        sourceUrl: Uri.parse('https://example.gov/assessor'),
        maxCharacters: 20000,
      );
      final content = WebPageContent(
        status: WebPageLoadStatus.success,
        requestedUrl: Uri.parse('https://example.gov/assessor'),
        text: extraction.plainText,
        blocks: extraction.blocks,
        outline: extraction.outline,
        structuredData: extraction.structuredData,
        contentMarkdown: rendered.markdown,
        omittedBlocks: extraction.omittedBlocks,
        boilerplateBlocks: rendered.boilerplateBlocks,
      );

      final json = content.toJson();
      expect(json['content'], rendered.markdown);
      expect(json.containsKey('text'), isFalse);
      expect(json['outline'], contains('# Property Search [b1-b7]'));
      expect(json['omittedBlocks'], 2);
      expect(json['suppressedBoilerplateBlocks'], 3);
    });

    test('keeps the legacy text shape without blocks', () {
      final content = WebPageContent(
        status: WebPageLoadStatus.success,
        requestedUrl: Uri.parse('https://example.com'),
        text: 'Readable page',
      );

      final json = content.toJson();
      expect(json['text'], 'Readable page');
      expect(json.containsKey('content'), isFalse);
      expect(json.containsKey('outline'), isFalse);
    });
  });
}
