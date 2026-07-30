// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../configured_agents/storage/key_value_store.dart';
import 'package:flutter/foundation.dart';

/// What the user chose to tell every agent about themselves.
///
/// A [ChangeNotifier] so the Settings row's summary updates the moment the
/// profile is saved. The values are read synchronously when an agent is built
/// for a conversation, so they are cached in memory and loaded once at
/// startup.
class UserProfileSettings extends ChangeNotifier {
  /// Creates a [UserProfileSettings] over [keyValueStore].
  UserProfileSettings(this._keyValueStore);

  static const String _nameKey = 'agents_app.profile.name';
  static const String _bioKey = 'agents_app.profile.bio';

  final KeyValueStore _keyValueStore;
  String _name = '';
  String _bio = '';

  /// What the user is called. Empty when unset.
  String get name => _name;

  /// A few lines about the user. Empty when unset.
  String get bio => _bio;

  /// Whether anything has been filled in.
  bool get isConfigured => _name.isNotEmpty || _bio.isNotEmpty;

  /// Loads the persisted profile.
  Future<void> load() async {
    _name = (await _keyValueStore.read(_nameKey) ?? '').trim();
    _bio = (await _keyValueStore.read(_bioKey) ?? '').trim();
    notifyListeners();
  }

  /// Persists [name] and [bio], applying them to the next agent turn.
  Future<void> save({required String name, required String bio}) async {
    _name = name.trim();
    _bio = bio.trim();
    notifyListeners();
    await _write(_nameKey, _name);
    await _write(_bioKey, _bio);
  }

  Future<void> _write(String key, String value) => value.isEmpty
      ? _keyValueStore.delete(key)
      : _keyValueStore.write(key, value);

  /// The profile as system instructions, or null when nothing is filled in.
  ///
  /// Phrased as a description of the person the agent is talking to rather
  /// than as a command, so it informs the reply without competing with the
  /// agent's own instructions.
  String? get instructions {
    if (!isConfigured) return null;
    final buffer = StringBuffer('About the person you are talking with:');
    if (_name.isNotEmpty) buffer.write('\nTheir name is $_name.');
    if (_bio.isNotEmpty) buffer.write('\n$_bio');
    return buffer.toString();
  }
}
