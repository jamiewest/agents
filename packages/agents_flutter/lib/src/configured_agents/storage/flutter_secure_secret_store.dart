// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secret_store.dart';

/// A [SecretStore] backed by `flutter_secure_storage`.
///
/// On mobile and desktop this uses the platform keychain/keystore. On the web
/// it falls back to browser storage, which does not provide real secret
/// protection; production web apps should proxy provider requests through a
/// backend instead of holding API keys client-side.
class FlutterSecureSecretStore extends SecretStore {
  /// Creates a store, optionally with a preconfigured [storage] instance.
  FlutterSecureSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
