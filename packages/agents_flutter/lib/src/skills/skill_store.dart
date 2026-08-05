// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import '../storage/record_store.dart';

import 'stored_skill.dart';

/// Persists [StoredSkill] records.
class SkillStore {
  /// Creates a [SkillStore] over [records].
  SkillStore(this._records);

  /// The record collection holding skills.
  static const String collection = 'agent_skills';

  final RecordStore _records;

  /// Generates a unique skill id.
  String newSkillId() {
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  /// Saves [skill].
  Future<void> save(StoredSkill skill) =>
      _records.put(collection, skill.id, skill.toRecord());

  /// Loads the skill with [id], or `null` when missing.
  Future<StoredSkill?> get(String id) async {
    final record = await _records.get(collection, id);
    return record == null ? null : StoredSkill.fromRecord(id, record);
  }

  /// Loads the skill named [name], or `null` when missing.
  Future<StoredSkill?> getByName(String name) async {
    final records = await _records.query(
      collection,
      query: RecordQuery(equals: {'name': name}, limit: 1),
    );
    if (records.isEmpty) return null;
    final record = records.first;
    return StoredSkill.fromRecord(record.id, record.value);
  }

  /// Deletes the skill with [id].
  Future<void> delete(String id) => _records.delete(collection, id);

  /// Lists all skills, ordered by name so the skills prompt built from them
  /// keeps a stable cached prefix between turns.
  Future<List<StoredSkill>> list() async {
    final records = await _records.query(
      collection,
      query: const RecordQuery(orderBy: 'name'),
    );
    return [
      for (final record in records)
        StoredSkill.fromRecord(record.id, record.value),
    ];
  }

  /// Watches all skills, ordered by name.
  Stream<List<StoredSkill>> watchAll() => _records
      .watch(collection, query: const RecordQuery(orderBy: 'name'))
      .map(
        (records) => [
          for (final record in records)
            StoredSkill.fromRecord(record.id, record.value),
        ],
      );
}
