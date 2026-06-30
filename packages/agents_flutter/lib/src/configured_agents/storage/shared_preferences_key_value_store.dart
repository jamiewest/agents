// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// A [KeyValueStore] backed by `shared_preferences`.
///
/// Suitable for the small JSON blobs that describe sources, models, and saved
/// agents. On the web this is backed by `localStorage`; see the package
/// documentation for the platform-specific storage caveats.
class SharedPreferencesKeyValueStore extends KeyValueStore {
  /// Creates a store. The underlying [SharedPreferences] instance is loaded
  /// lazily on first use, or you may supply [preferences] directly (useful for
  /// tests via `SharedPreferences.setMockInitialValues`).
  SharedPreferencesKeyValueStore({SharedPreferences? preferences})
    : _preferences = preferences;

  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await _instance()).setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await (await _instance()).remove(key);
  }

  @override
  Future<List<String>> keys({String prefix = ''}) async => (await _instance())
      .getKeys()
      .where((key) => key.startsWith(prefix))
      .toList(growable: false);
}
