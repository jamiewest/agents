// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:sembast/sembast.dart' as sembast;

import 'record_store.dart';
import 'sembast_database.dart';

/// A [RecordStore] backed by a sembast database.
///
/// Works on native platforms (file-backed) and the web (IndexedDB) through
/// [openSembastDatabase]. Each collection maps to one sembast store.
class SembastRecordStore extends RecordStore {
  /// Creates a [SembastRecordStore] over an already-opening [database].
  ///
  /// A store created this way does not know how to recreate its database,
  /// so [clearAll] is unsupported; use [SembastRecordStore.open] when the
  /// full-reset path matters.
  SembastRecordStore(Future<sembast.Database> database)
    : _database = database,
      _name = null;

  /// Creates a [SembastRecordStore] over the platform-default database.
  SembastRecordStore.open({String name = 'agents_app.db'})
    : _database = openSembastDatabase(name: name),
      _name = name;

  Future<sembast.Database> _database;
  final String? _name;

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
  Future<void> putAll(
    String collection,
    Map<String, Map<String, Object?>> records,
  ) async {
    if (records.isEmpty) return;
    final database = await _database;
    final store = _store(collection);
    await database.transaction((transaction) async {
      for (final entry in records.entries) {
        await store.record(entry.key).put(transaction, entry.value);
      }
    });
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

  @override
  Future<void> clearAll() async {
    final name = _name;
    if (name == null) {
      throw UnsupportedError(
        'clearAll requires a store created with SembastRecordStore.open, '
        'which knows the database name needed to delete and recreate it.',
      );
    }
    // Sembast cannot enumerate its stores, so the only complete wipe is to
    // delete the database itself and reopen an empty one. Watch streams
    // created before the reset stay bound to the closed database.
    //
    // The replacement future is swapped in before the close so operations
    // that start mid-reset await the reopened database instead of throwing
    // on the closed one.
    final previous = _database;
    final replacement = Completer<sembast.Database>();
    _database = replacement.future;
    try {
      final database = await previous;
      await database.close();
      await deleteSembastDatabase(name: name);
      replacement.complete(await openSembastDatabase(name: name));
    } catch (error, stackTrace) {
      replacement.completeError(error, stackTrace);
      replacement.future.ignore();
      rethrow;
    }
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
