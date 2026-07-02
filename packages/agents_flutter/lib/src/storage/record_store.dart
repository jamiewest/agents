// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A persistent JSON-document store with named collections.
///
/// High-volume application data (conversations, messages, channels, tasks,
/// memory records) lives here, keyed by id within a collection. Low-volume
/// configuration stays in `KeyValueStore`.
///
/// Implementations must treat stored maps as JSON-compatible: values are
/// `null`, `bool`, `int`, `double`, `String`, `List`, or `Map` thereof.
abstract class RecordStore {
  /// Creates a [RecordStore].
  const RecordStore();

  /// Returns the record with [id] in [collection], or `null` when missing.
  Future<Map<String, Object?>?> get(String collection, String id);

  /// Inserts or replaces the record with [id] in [collection].
  Future<void> put(String collection, String id, Map<String, Object?> record);

  /// Deletes the record with [id] from [collection] if it exists.
  Future<void> delete(String collection, String id);

  /// Returns the records in [collection] matching [query].
  ///
  /// A `null` [query] returns every record in the collection.
  Future<List<StoredRecord>> query(String collection, {RecordQuery? query});

  /// Watches [collection], emitting the current [query] results immediately
  /// and again after every change to the collection.
  Stream<List<StoredRecord>> watch(String collection, {RecordQuery? query});

  /// Deletes every record in [collection] matching [query].
  Future<void> deleteWhere(String collection, RecordQuery query);
}

/// A record returned from a [RecordStore] query.
class StoredRecord {
  /// Creates a [StoredRecord].
  const StoredRecord(this.id, this.value);

  /// The record id within its collection.
  final String id;

  /// The stored JSON-compatible record value.
  final Map<String, Object?> value;
}

/// A declarative query over one [RecordStore] collection.
///
/// Supports field-equality filters, single-field ordering, and paging —
/// deliberately no more, so it maps directly onto simple backends.
class RecordQuery {
  /// Creates a [RecordQuery].
  const RecordQuery({
    this.equals = const {},
    this.orderBy,
    this.descending = false,
    this.limit,
    this.offset,
  });

  /// Field values a record must match exactly (logical AND).
  final Map<String, Object?> equals;

  /// The field to order results by, or `null` for backend order.
  final String? orderBy;

  /// Whether [orderBy] sorts descending.
  final bool descending;

  /// Maximum number of records to return.
  final int? limit;

  /// Number of matching records to skip before returning results.
  final int? offset;
}
