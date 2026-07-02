// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions/system.dart';
import 'package:extensions/vector_data.dart';

import '../storage/record_store.dart';
import 'memory_scorer.dart';

/// A [VectorStore] persisted through a [RecordStore], sized for on-device
/// agent memory.
///
/// Records live in the `memory.<collection>` record collection. The single
/// vector property of the collection definition carries raw text on upsert
/// (matching `ChatHistoryMemoryProvider`); the store embeds it via its
/// [MemoryScorer] and ranks search candidates in memory — appropriate at
/// personal-app scale.
///
/// Only dynamic collections are supported, and search filters are limited
/// to `equalTo`/`and` (which map onto record-store field equality).
class RecordStoreVectorStore extends VectorStore {
  /// Creates a [RecordStoreVectorStore].
  RecordStoreVectorStore(this._records, {MemoryScorer? scorer})
    : _scorer = scorer ?? const KeywordOverlapScorer();

  static const String _registryCollection = 'memory.collections';
  static const String _vectorField = '_vector';

  final RecordStore _records;
  final MemoryScorer _scorer;

  static String _collectionKey(String name) => 'memory.$name';

  @override
  VectorStoreCollection<TKey, TRecord> getCollection<TKey, TRecord>(
    String name, {
    VectorStoreCollectionDefinition? definition,
  }) => throw UnsupportedError(
    'RecordStoreVectorStore only supports dynamic collections.',
  );

  @override
  VectorStoreCollection<String, Map<String, Object?>> getDynamicCollection(
    String name,
    VectorStoreCollectionDefinition definition,
  ) => _RecordStoreVectorCollection(this, name, definition);

  @override
  Stream<String> listCollectionNamesAsync({
    CancellationToken? cancellationToken,
  }) async* {
    final entries = await _records.query(_registryCollection);
    for (final entry in entries) {
      yield entry.id;
    }
  }

  @override
  Future<bool> collectionExistsAsync(
    String name, {
    CancellationToken? cancellationToken,
  }) async => await _records.get(_registryCollection, name) != null;

  @override
  Future<void> ensureCollectionDeletedAsync(
    String name, {
    CancellationToken? cancellationToken,
  }) async {
    await _records.deleteWhere(_collectionKey(name), const RecordQuery());
    await _records.delete(_registryCollection, name);
  }
}

class _RecordStoreVectorCollection
    extends VectorStoreCollection<String, Map<String, Object?>> {
  _RecordStoreVectorCollection(this._store, this._name, this._definition);

  final RecordStoreVectorStore _store;
  final String _name;
  final VectorStoreCollectionDefinition _definition;

  RecordStore get _records => _store._records;
  String get _collection => RecordStoreVectorStore._collectionKey(_name);

  String get _keyField => _definition.keyProperties.single.propertyName;

  String? get _vectorTextField {
    final vectors = _definition.vectorProperties;
    return vectors.isEmpty ? null : vectors.first.propertyName;
  }

  @override
  String get name => _name;

  @override
  Future<bool> collectionExistsAsync({CancellationToken? cancellationToken}) =>
      _store.collectionExistsAsync(_name);

  @override
  Future<void> ensureCollectionExistsAsync({
    CancellationToken? cancellationToken,
  }) => _records.put(RecordStoreVectorStore._registryCollection, _name, {
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  });

  @override
  Future<void> ensureCollectionDeletedAsync({
    CancellationToken? cancellationToken,
  }) => _store.ensureCollectionDeletedAsync(_name);

  @override
  Future<Map<String, Object?>?> getAsync(
    String key, {
    RecordRetrievalOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final record = await _records.get(_collection, key);
    return record == null ? null : _withoutVector(record);
  }

  @override
  Stream<Map<String, Object?>> getBatchAsync(
    Iterable<String> keys, {
    RecordRetrievalOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    for (final key in keys) {
      final record = await getAsync(key, cancellationToken: cancellationToken);
      if (record != null) yield record;
    }
  }

  @override
  Stream<Map<String, Object?>> getFilteredAsync({
    VectorStoreFilter? filter,
    int? top,
    FilteredRecordRetrievalOptions<Map<String, Object?>>? options,
    CancellationToken? cancellationToken,
  }) async* {
    final results = await _records.query(
      _collection,
      query: RecordQuery(equals: _translateFilter(filter), limit: top),
    );
    for (final result in results) {
      yield _withoutVector(result.value);
    }
  }

  @override
  Future<String> upsertAsync(
    Map<String, Object?> record, {
    CancellationToken? cancellationToken,
  }) async {
    final key = record[_keyField]! as String;
    final stored = Map<String, Object?>.of(record);
    final textField = _vectorTextField;
    if (textField != null && record[textField] is String) {
      final vector = await _store._scorer.embed(record[textField]! as String);
      if (vector != null) {
        stored[RecordStoreVectorStore._vectorField] = vector;
      }
    }
    await _records.put(_collection, key, stored);
    return key;
  }

  @override
  Stream<String> upsertBatchAsync(
    Iterable<Map<String, Object?>> records, {
    CancellationToken? cancellationToken,
  }) async* {
    for (final record in records) {
      yield await upsertAsync(record, cancellationToken: cancellationToken);
    }
  }

  @override
  Future<void> deleteAsync(
    String key, {
    CancellationToken? cancellationToken,
  }) => _records.delete(_collection, key);

  @override
  Future<void> deleteBatchAsync(
    Iterable<String> keys, {
    CancellationToken? cancellationToken,
  }) async {
    for (final key in keys) {
      await deleteAsync(key, cancellationToken: cancellationToken);
    }
  }

  @override
  Stream<VectorSearchResult<Map<String, Object?>>> searchAsync<TInput>(
    TInput value, {
    int top = 3,
    VectorSearchOptions<Map<String, Object?>>? options,
    CancellationToken? cancellationToken,
  }) async* {
    final queryText = value.toString();
    final queryVector = await _store._scorer.embed(queryText);
    final textField = _vectorTextField;

    final candidates = await _records.query(
      _collection,
      query: RecordQuery(equals: _translateFilter(options?.filter)),
    );

    final scored = <(Map<String, Object?>, double)>[
      for (final candidate in candidates)
        (
          candidate.value,
          _store._scorer.score(
            queryText: queryText,
            recordText: textField == null
                ? ''
                : candidate.value[textField]?.toString() ?? '',
            queryVector: queryVector,
            recordVector: _vectorOf(candidate.value),
          ),
        ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    final threshold = options?.scoreThreshold;
    var emitted = 0;
    for (final (record, score) in scored.skip(options?.skip ?? 0)) {
      if (emitted >= top) break;
      if (threshold != null && score < threshold) continue;
      emitted++;
      yield VectorSearchResult(_withoutVector(record), score: score);
    }
  }

  /// Maps `equalTo`/`and` filters onto record-store field equality.
  static Map<String, Object?> _translateFilter(VectorStoreFilter? filter) =>
      switch (filter) {
        null => const {},
        EqualToVectorStoreFilter(:final fieldName, :final value) => {
          fieldName: value,
        },
        AndVectorStoreFilter(:final filters) => {
          for (final child in filters) ..._translateFilter(child),
        },
        _ => throw UnsupportedError(
          'RecordStoreVectorStore supports only equalTo/and filters.',
        ),
      };

  static List<double>? _vectorOf(Map<String, Object?> record) =>
      switch (record[RecordStoreVectorStore._vectorField]) {
        final List<Object?> values => [
          for (final value in values) (value! as num).toDouble(),
        ],
        _ => null,
      };

  static Map<String, Object?> _withoutVector(Map<String, Object?> record) =>
      Map.of(record)..remove(RecordStoreVectorStore._vectorField);
}
