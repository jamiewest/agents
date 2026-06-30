// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A secure store for provider secrets such as API keys.
///
/// Secrets are kept entirely separate from the non-secret configuration JSON
/// held in a `KeyValueStore`: nothing written here is ever serialized into a
/// source, model, or agent's JSON. The default production implementation is
/// backed by `flutter_secure_storage`.
abstract class SecretStore {
  /// Creates a [SecretStore].
  const SecretStore();

  /// Returns the secret stored for [key], or `null` when absent.
  Future<String?> read(String key);

  /// Writes [value] for [key], replacing any existing secret.
  Future<void> write(String key, String value);

  /// Removes the secret stored for [key]. A no-op when [key] is absent.
  Future<void> delete(String key);
}
