// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:sembast/sembast.dart' as sembast;

import 'record_store.dart';
import 'sembast_database.dart';

/// A [RecordStore] backed by a sembast database.
///
/// Works on native platforms (file-backed) and the web (IndexedDB) through
/// [openSembastDatabase]. Each collection maps to one sembast store.
class SembastRecordStore extends RecordStore {
  /// Creates a [SembastRecordStore] over an already-opening [database].
  SembastRecordStore(Future<sembast.Database> database) : _database = database;

  /// Creates a [SembastRecordStore] over the platform-default database.
  SembastRecordStore.open({String name = 'agents_app.db'})
    : _database = openSembastDatabase(name: name);

  final Future<sembast.Database> _database;

  static sembast.StoreRef<String, Map<String, Object?>> _store(
    String collection,
  ) => sembast.stringMapStoreFactory.store(collection);

  @override
  Future<Map<String, Object?>?> get(String collection, String id) async {
    final database = await _database;
    final record = await _store(collection).record(id).get(database);
    return record == null ? null : Map<String, Object?>.of(record);
  }

  @override
  Future<void> put(
    String collection,
    String id,
    Map<String, Object?> record,
  ) async {
    final database = await _database;
    await _store(collection).record(id).put(database, record);
  }

  @override
  Future<void> delete(String collection, String id) async {
    final database = await _database;
    await _store(collection).record(id).delete(database);
  }

  @override
  Future<List<StoredRecord>> query(
    String collection, {
    RecordQuery? query,
  }) async {
    final database = await _database;
    final snapshots = await _store(
      collection,
    ).find(database, finder: _finder(query));
    return [
      for (final snapshot in snapshots)
        StoredRecord(snapshot.key, Map<String, Object?>.of(snapshot.value)),
    ];
  }

  @override
  Stream<List<StoredRecord>> watch(String collection, {RecordQuery? query}) =>
      Stream.fromFuture(_database).asyncExpand(
        (database) => _store(collection)
            .query(finder: _finder(query))
            .onSnapshots(database)
            .map(
              (snapshots) => [
                for (final snapshot in snapshots)
                  StoredRecord(
                    snapshot.key,
                    Map<String, Object?>.of(snapshot.value),
                  ),
              ],
            ),
      );

  @override
  Future<void> deleteWhere(String collection, RecordQuery query) async {
    final database = await _database;
    await _store(collection).delete(database, finder: _finder(query));
  }

  static sembast.Finder? _finder(RecordQuery? query) {
    if (query == null) {
      return null;
    }

    sembast.Filter? filter;
    if (query.equals.isNotEmpty) {
      final conditions = [
        for (final condition in query.equals.entries)
          sembast.Filter.equals(condition.key, condition.value),
      ];
      filter = conditions.length == 1
          ? conditions.single
          : sembast.Filter.and(conditions);
    }

    final orderBy = query.orderBy;
    return sembast.Finder(
      filter: filter,
      sortOrders: orderBy == null
          ? null
          : [sembast.SortOrder(orderBy, !query.descending)],
      limit: query.limit,
      offset: query.offset,
    );
  }
}
