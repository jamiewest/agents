// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'key_value_store.dart';

/// An in-memory [KeyValueStore] backed by a [Map].
///
/// Intended for tests and ephemeral usage. Nothing is persisted across process
/// restarts.
class InMemoryKeyValueStore extends KeyValueStore {
  /// Creates an [InMemoryKeyValueStore], optionally seeded with [initial]
  /// entries.
  InMemoryKeyValueStore([Map<String, String>? initial])
    : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<List<String>> keys({String prefix = ''}) async => _values.keys
      .where((key) => key.startsWith(prefix))
      .toList(growable: false);
}
