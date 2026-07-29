import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// An assessor-guide page: general intro, a history section, a fees
/// section with a short intro and a table, contact info, nav chrome, and
/// a repeated paragraph.
WebPageExtraction _extraction() => WebPageExtraction.parse(<String, Object?>{
  'meta': <String, Object?>{'title': 'Assessor Guide'},
  'blocks': <Object?>[
    <String, Object?>{
      'kind': 'heading',
      'level': 1,
      'text': 'Assessor Guide',
      'container': 'main',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': 'General information about the county assessor office.',
      'container': 'main',
    },
    <String, Object?>{
      'kind': 'heading',
      'level': 2,
      'text': 'History',
      'container': 'main',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': 'The office was founded in 1850 and has served the county.',
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
      'text': 'The following charges apply.',
      'container': 'main',
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
    },
    <String, Object?>{
      'kind': 'heading',
      'level': 2,
      'text': 'Contact',
      'container': 'main',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': 'Call the office to make an appointment for records help.',
      'container': 'main',
    },
    <String, Object?>{
      'kind': 'list',
      'text': '',
      'items': <Object?>['Home', 'Departments'],
      'container': 'nav',
    },
    <String, Object?>{
      'kind': 'paragraph',
      'text': 'The office was founded in 1850 and has served the county.',
      'container': 'main',
    },
  ],
});

void main() {
  group('LexicalBlockScorer', () {
    test('ranks matching tables above unrelated text', () async {
      final blocks = _extraction().blocks;
      final scores = await const LexicalBlockScorer().score(
        'How much does the assessment roll cost?',
        blocks,
      );

      expect(scores[6], greaterThan(0), reason: 'fee table matches');
      expect(scores[3], 0, reason: 'history matches nothing');
      expect(scores[9], 0, reason: 'boilerplate never scores');
      expect(scores[10], 0, reason: 'duplicates never score');
    });

    test('credits blocks through their heading path', () async {
      final blocks = _extraction().blocks;
      final scores = await const LexicalBlockScorer().score('fees', blocks);

      expect(
        scores[5],
        greaterThan(0),
        reason: 'intro under the Fees heading matches by path alone',
      );
      expect(scores[8], 0);
    });
  });

  group('selectQueryEvidence', () {
    test('brings headings and short intros along with a match', () async {
      final selection = await selectQueryEvidence(
        blocks: _extraction().blocks,
        query: 'assessment roll charges',
        maxCharacters: 20000,
      );

      expect(selection.anyMatch, isTrue);
      expect(
        selection.blocks.map((block) => block.id),
        containsAll(<String>['b0', 'b4', 'b5', 'b6']),
        reason: 'table travels with its headings and intro',
      );
      expect(selection.blocks.map((block) => block.id), isNot(contains('b3')));
    });

    test('reports no match instead of guessing', () async {
      final selection = await selectQueryEvidence(
        blocks: _extraction().blocks,
        query: 'quantum chromodynamics',
        maxCharacters: 20000,
      );

      expect(selection.anyMatch, isFalse);
      expect(selection.blocks, isEmpty);
    });

    test('keeps the best match even under a tiny budget', () async {
      final selection = await selectQueryEvidence(
        blocks: _extraction().blocks,
        query: 'assessment roll charges',
        maxCharacters: 10,
      );

      expect(selection.anyMatch, isTrue);
      expect(selection.blocks, isNotEmpty);
    });
  });

  group('buildQueryAwareEvidence', () {
    test('renders the focused package with gaps and honest counts', () async {
      final extraction = _extraction();
      final content = WebPageContent(
        status: WebPageLoadStatus.success,
        requestedUrl: Uri.parse('https://example.gov/assessor'),
        title: extraction.title,
        blocks: extraction.blocks,
        outline: extraction.outline,
      );

      final evidence = await buildQueryAwareEvidence(
        content: content,
        objective: 'How much does the assessment roll cost?',
        maxCharacters: 20000,
      );

      expect(evidence.anyMatch, isTrue);
      expect(evidence.markdown, contains('Focused on: How much'));
      expect(evidence.markdown, contains('### Fees'));
      expect(evidence.markdown, contains(r'| Electronic | $25 |'));
      expect(evidence.markdown, contains('[…]'));
      expect(evidence.markdown, isNot(contains('founded in 1850')));
      expect(evidence.omittedContentBlocks, greaterThan(0));
    });
  });

  group('duplicate marking', () {
    test('marks repeats, skips them in markdown, keeps them expandable', () {
      final extraction = _extraction();

      final duplicate = extraction.blocks[10];
      expect(duplicate.duplicateOfIndex, 3);
      expect(duplicate.toJson()['duplicateOf'], 'b3');

      final rendered = renderWebPageMarkdown(
        extraction: extraction,
        sourceUrl: Uri.parse('https://example.gov/assessor'),
        maxCharacters: 20000,
      );
      expect(
        RegExp('founded in 1850').allMatches(rendered.markdown),
        hasLength(1),
        reason: 'the duplicate renders once',
      );
    });

    test('short repeats are not marked as duplicates', () {
      final extraction = WebPageExtraction.parse(<String, Object?>{
        'blocks': <Object?>[
          <String, Object?>{'kind': 'paragraph', 'text': 'Fees'},
          <String, Object?>{'kind': 'paragraph', 'text': 'Fees'},
        ],
      });

      expect(extraction.blocks[1].duplicateOfIndex, isNull);
    });
  });
}
