// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'secret_store.dart';

/// An in-memory [SecretStore] backed by a [Map].
///
/// Intended for tests and ephemeral usage; it provides no real secret
/// protection and persists nothing across process restarts.
class InMemorySecretStore extends SecretStore {
  /// Creates an [InMemorySecretStore], optionally seeded with [initial]
  /// secrets.
  InMemorySecretStore([Map<String, String>? initial])
    : _secrets = {...?initial};

  final Map<String, String> _secrets;

  @override
  Future<String?> read(String key) async => _secrets[key];

  @override
  Future<void> write(String key, String value) async {
    _secrets[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _secrets.remove(key);
  }
}
