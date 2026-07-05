// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'record_store.dart';

/// An in-memory [RecordStore] for tests and ephemeral use.
class InMemoryRecordStore extends RecordStore {
  /// Creates an [InMemoryRecordStore], optionally seeded with
  /// collection → id → record data.
  InMemoryRecordStore([Map<String, Map<String, Map<String, Object?>>>? seed]) {
    if (seed != null) {
      for (final entry in seed.entries) {
        _collections[entry.key] = {
          for (final record in entry.value.entries)
            record.key: Map<String, Object?>.of(record.value),
        };
      }
    }
  }

  final Map<String, Map<String, Map<String, Object?>>> _collections = {};
  final StreamController<String> _changes = StreamController.broadcast();

  Map<String, Map<String, Object?>> _collection(String collection) =>
      _collections.putIfAbsent(collection, () => {});

  @override
  Future<Map<String, Object?>?> get(String collection, String id) async {
    final record = _collection(collection)[id];
    return record == null ? null : Map<String, Object?>.of(record);
  }

  @override
  Future<void> put(
    String collection,
    String id,
    Map<String, Object?> record,
  ) async {
    _collection(collection)[id] = Map<String, Object?>.of(record);
    _changes.add(collection);
  }

  @override
  Future<void> delete(String collection, String id) async {
    _collection(collection).remove(id);
    _changes.add(collection);
  }

  @override
  Future<List<StoredRecord>> query(
    String collection, {
    RecordQuery? query,
  }) async => _query(collection, query);

  @override
  Stream<List<StoredRecord>> watch(String collection, {RecordQuery? query}) {
    late StreamController<List<StoredRecord>> controller;
    StreamSubscription<String>? subscription;

    void emit() => controller.add(_query(collection, query));

    controller = StreamController<List<StoredRecord>>(
      onListen: () {
        emit();
        subscription = _changes.stream
            .where((changed) => changed == collection)
            .listen((_) => emit());
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> clearAll() async {
    final collections = _collections.keys.toList();
    _collections.clear();
    for (final collection in collections) {
      _changes.add(collection);
    }
  }

  @override
  Future<void> deleteWhere(String collection, RecordQuery query) async {
    final matches = _query(collection, query);
    final records = _collection(collection);
    for (final match in matches) {
      records.remove(match.id);
    }
    _changes.add(collection);
  }

  List<StoredRecord> _query(String collection, RecordQuery? query) {
    Iterable<StoredRecord> results = _collection(
      collection,
    ).entries.map((entry) => StoredRecord(entry.key, Map.of(entry.value)));

    final equals = query?.equals ?? const {};
    if (equals.isNotEmpty) {
      results = results.where(
        (record) => equals.entries.every(
          (condition) => record.value[condition.key] == condition.value,
        ),
      );
    }

    var list = results.toList();
    final orderBy = query?.orderBy;
    if (orderBy != null) {
      list.sort((a, b) {
        final left = a.value[orderBy];
        final right = b.value[orderBy];
        final comparison = _compare(left, right);
        return query!.descending ? -comparison : comparison;
      });
    }

    final offset = query?.offset;
    if (offset != null && offset > 0) {
      list = list.skip(offset).toList();
    }
    final limit = query?.limit;
    if (limit != null && list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  static int _compare(Object? left, Object? right) {
    if (left == null && right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;
    if (left is num && right is num) return left.compareTo(right);
    if (left is String && right is String) return left.compareTo(right);
    if (left is bool && right is bool) {
      return (left ? 1 : 0).compareTo(right ? 1 : 0);
    }
    return left.toString().compareTo(right.toString());
  }
}
