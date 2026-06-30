// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A minimal asynchronous string key/value store.
///
/// Used to persist the non-secret configuration JSON for sources, models, and
/// saved agents. Secrets such as API keys must never be written here; use a
/// `SecretStore` for those.
///
/// Implementations are swappable so that the configuration stores can be tested
/// against an in-memory backend.
abstract class KeyValueStore {
  /// Creates a [KeyValueStore].
  const KeyValueStore();

  /// Returns the value stored for [key], or `null` when absent.
  Future<String?> read(String key);

  /// Writes [value] for [key], replacing any existing value.
  Future<void> write(String key, String value);

  /// Removes the value stored for [key]. A no-op when [key] is absent.
  Future<void> delete(String key);

  /// Returns every key currently present that begins with [prefix].
  Future<List<String>> keys({String prefix = ''});
}
