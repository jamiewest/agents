// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:extensions/ai.dart';

/// Embeds memory text and scores query relevance for
/// `RecordStoreVectorStore`.
///
/// The store calls [embed] when records are written (and for the query at
/// search time) and [score] to rank candidates. Implementations that cannot
/// embed return `null` vectors and score by text alone.
abstract class MemoryScorer {
  /// Creates a [MemoryScorer].
  const MemoryScorer();

  /// Returns an embedding for [text], or `null` when embedding is
  /// unavailable.
  Future<List<double>?> embed(String text);

  /// Scores how relevant a stored record is to a query. Higher is better.
  double score({
    required String queryText,
    required String recordText,
    List<double>? queryVector,
    List<double>? recordVector,
  });
}

/// Scores by word overlap; stores no vectors.
///
/// The zero-configuration default: works with no embedding model, degrades
/// gracefully, and can be replaced later without touching stored text.
class KeywordOverlapScorer extends MemoryScorer {
  /// Creates a [KeywordOverlapScorer].
  const KeywordOverlapScorer();

  @override
  Future<List<double>?> embed(String text) async => null;

  @override
  double score({
    required String queryText,
    required String recordText,
    List<double>? queryVector,
    List<double>? recordVector,
  }) {
    final query = _tokens(queryText);
    final record = _tokens(recordText);
    if (query.isEmpty || record.isEmpty) return 0;
    final intersection = query.intersection(record).length;
    final union = query.union(record).length;
    return intersection / union;
  }

  static Set<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length > 1)
      .toSet();
}

/// Embeds with an [EmbeddingGenerator] and scores by cosine similarity.
///
/// Records stored before an embedding model was configured have no vector;
/// those fall back to keyword overlap so they remain retrievable.
class EmbeddingGeneratorScorer extends MemoryScorer {
  /// Creates an [EmbeddingGeneratorScorer] over [generator].
  const EmbeddingGeneratorScorer(this._generator);

  final EmbeddingGenerator _generator;
  static const _fallback = KeywordOverlapScorer();

  @override
  Future<List<double>?> embed(String text) async {
    final embeddings = await _generator.generateEmbeddings(values: [text]);
    return embeddings[0].vector;
  }

  @override
  double score({
    required String queryText,
    required String recordText,
    List<double>? queryVector,
    List<double>? recordVector,
  }) {
    if (queryVector == null || recordVector == null) {
      return _fallback.score(queryText: queryText, recordText: recordText);
    }
    return cosineSimilarity(queryVector, recordVector);
  }

  /// Cosine similarity of two vectors; 0 when lengths differ or either is
  /// zero.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
