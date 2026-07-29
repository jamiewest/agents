import 'dart:math';

import 'web_content_block.dart';

/// Scores page blocks against a query, higher meaning more relevant.
///
/// The seam the evidence pipeline ranks through. The built-in
/// [LexicalBlockScorer] is deterministic and local; hosts can substitute a
/// semantic scorer (embeddings) without touching the tools. Scores are
/// internal ranking signals only — they are never exposed to the model.
abstract interface class BlockScorer {
  /// Returns one score per entry in [blocks], aligned by index.
  ///
  /// Boilerplate and duplicate blocks may be given any score; the
  /// selection layer excludes them regardless.
  Future<List<double>> score(String query, List<WebContentBlock> blocks);
}

/// The default lexical and structural scorer.
///
/// Combines BM25-style term scoring over block text with the structural
/// signals the page gives away for free:
///
/// - **Heading-path credit** — a block under a "Fees" heading earns fee-term
///   credit even when its own text only says "Electronic copies are $25".
/// - **Type weights** — tables and definition lists get a boost when the
///   query looks numeric (digits, currency, price/fee/cost words), since
///   that is where such answers live.
/// - **Positional prior** — earlier content is slightly favored on ties.
///
/// Boilerplate and duplicate blocks score zero.
class LexicalBlockScorer implements BlockScorer {
  /// Creates the lexical scorer.
  const LexicalBlockScorer();

  static const double _k1 = 1.2;
  static const double _b = 0.75;
  static const double _headingCredit = 0.8;
  static const double _numericTypeBoost = 1.3;
  static const double _positionalRange = 0.15;

  static const Set<String> _stopwords = <String>{
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'did',
    'do',
    'does',
    'for',
    'from',
    'has',
    'have',
    'how',
    'in',
    'is',
    'it',
    'its',
    'no',
    'not',
    'of',
    'on',
    'or',
    'that',
    'the',
    'this',
    'to',
    'was',
    'what',
    'when',
    'where',
    'which',
    'who',
    'why',
    'will',
    'with',
    'you',
    'your',
  };

  static const Set<String> _numericQueryWords = <String>{
    'amount',
    'charge',
    'charges',
    'cost',
    'costs',
    'fee',
    'fees',
    'much',
    'pay',
    'price',
    'prices',
    'rate',
    'rates',
  };

  static final RegExp _tokenPattern = RegExp(r'[a-z0-9]+');
  static final RegExp _numericSignal = RegExp(r'[0-9$€£]');

  @override
  Future<List<double>> score(String query, List<WebContentBlock> blocks) {
    final terms = _tokenize(
      query,
    ).where((t) => !_stopwords.contains(t)).toSet();
    if (terms.isEmpty || blocks.isEmpty) {
      return Future.value(List<double>.filled(blocks.length, 0));
    }
    final numericQuery =
        _numericSignal.hasMatch(query) ||
        _tokenize(query).any(_numericQueryWords.contains);

    // Term statistics over the scorable blocks only, so chrome cannot
    // dilute document frequencies.
    final blockTerms = <int, Map<String, int>>{};
    var totalLength = 0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (!_scorable(block)) continue;
      final counts = <String, int>{};
      for (final token in _tokenize(_searchableText(block))) {
        counts[token] = (counts[token] ?? 0) + 1;
      }
      blockTerms[i] = counts;
      totalLength += counts.values.fold(0, (sum, n) => sum + n);
    }
    if (blockTerms.isEmpty) {
      return Future.value(List<double>.filled(blocks.length, 0));
    }
    final blockCount = blockTerms.length;
    final averageLength = max(totalLength / blockCount, 1);
    final documentFrequency = <String, int>{
      for (final term in terms)
        term: blockTerms.values
            .where((counts) => counts.containsKey(term))
            .length,
    };
    double idf(String term) {
      final df = documentFrequency[term] ?? 0;
      return log(1 + (blockCount - df + 0.5) / (df + 0.5));
    }

    final lastIndex = max(blocks.length - 1, 1);
    final scores = List<double>.filled(blocks.length, 0);
    for (final entry in blockTerms.entries) {
      final block = blocks[entry.key];
      final counts = entry.value;
      final length = counts.values.fold(0, (sum, n) => sum + n);
      var score = 0.0;
      for (final term in terms) {
        final tf = counts[term] ?? 0;
        if (tf > 0) {
          score +=
              idf(term) *
              (tf * (_k1 + 1)) /
              (tf + _k1 * (1 - _b + _b * length / averageLength));
        }
        if (_headingTokens(block).contains(term)) {
          score += idf(term) * _headingCredit;
        }
      }
      if (score == 0) continue;
      score *= _typeWeight(block.type, numericQuery: numericQuery);
      score *= 1 - _positionalRange * (block.index / lastIndex);
      scores[entry.key] = score;
    }
    return Future.value(scores);
  }

  static bool _scorable(WebContentBlock block) =>
      !block.isBoilerplate &&
      block.duplicateOfIndex == null &&
      block.type != WebContentBlockType.heading;

  static String _searchableText(WebContentBlock block) => [
    block.text,
    ...block.listItems,
    if (block.table case final table?) ...[
      ...table.columns,
      for (final row in table.rows) ...row,
      ?table.caption,
    ],
    for (final link in block.links) link.text,
  ].join(' ');

  static Set<String> _headingTokens(WebContentBlock block) => {
    for (final heading in block.headingPath) ..._tokenize(heading),
  };

  static double _typeWeight(
    WebContentBlockType type, {
    required bool numericQuery,
  }) => switch (type) {
    WebContentBlockType.table ||
    WebContentBlockType.definition => numericQuery ? _numericTypeBoost : 1.1,
    WebContentBlockType.media => 0.6,
    WebContentBlockType.form => 0.8,
    _ => 1.0,
  };

  static List<String> _tokenize(String text) => [
    for (final match in _tokenPattern.allMatches(text.toLowerCase()))
      match.group(0)!,
  ];
}
