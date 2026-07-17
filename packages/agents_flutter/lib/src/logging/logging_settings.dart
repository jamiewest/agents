// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/logging.dart';
import 'package:flutter/foundation.dart';

import '../configured_agents/storage/key_value_store.dart';

/// The runtime-adjustable log filter: a global minimum level plus
/// per-category overrides.
///
/// The app logging registration installs a dynamic filter rule that consults
/// this object on every log call, so changes made from a settings UI take
/// effect immediately — no logger or host rebuild required. Because the rule
/// also drives `Logger.isEnabled`, lowering a category below `trace` skips
/// the expensive payload rendering that trace-level loggers (such as the
/// framework's `LoggingAgent`) perform per streamed update.
///
/// A category override applies to the exact category and to dotted
/// sub-categories: an override for `Agents` also covers `Agents.Traffic`.
/// An override of [LogLevel.none] silences the category entirely.
class LoggingSettings extends ChangeNotifier {
  /// Creates settings with [defaultLevel] as the global minimum.
  LoggingSettings({LogLevel defaultLevel = LogLevel.information})
    : _minimumLevel = defaultLevel;

  static const String _minimumLevelKey = 'agents_flutter.logging.minimum_level';
  static const String _categoryLevelsKey =
      'agents_flutter.logging.category_levels';

  KeyValueStore? _store;
  LogLevel _minimumLevel;
  final Map<String, LogLevel> _categoryLevels = <String, LogLevel>{};

  // Changes made before bindStore completes must win over the loaded values
  // (and still be persisted once the store is bound), so track which fields
  // have been touched.
  bool _minimumLevelTouched = false;
  bool _categoryLevelsTouched = false;

  // The extensions package defines a `name` extension on LogLevel that
  // returns `LogLevel.Trace`-style strings, shadowing `EnumName.name`; use
  // the plain enum identifier for stable persistence.
  static String _levelName(LogLevel level) => level.toString().split('.').last;

  /// The minimum level for categories without an override.
  LogLevel get minimumLevel => _minimumLevel;

  /// Per-category minimum levels, keyed by category (or category prefix).
  Map<String, LogLevel> get categoryLevels =>
      Map<String, LogLevel>.unmodifiable(_categoryLevels);

  /// Loads persisted values from [store] and persists future changes to it.
  ///
  /// Values changed before the load completes (for example from a settings
  /// UI during startup) are kept and persisted rather than overwritten by
  /// the loaded state.
  Future<void> bindStore(KeyValueStore store) async {
    _store = store;
    final storedLevel = await store.read(_minimumLevelKey);
    final storedOverrides = await store.read(_categoryLevelsKey);
    if (_minimumLevelTouched) {
      await store.write(_minimumLevelKey, _levelName(_minimumLevel));
    } else {
      final level = LogLevel.values.asNameMap()[storedLevel];
      if (level != null) _minimumLevel = level;
    }
    if (_categoryLevelsTouched) {
      await _persistOverrides();
    } else if (storedOverrides != null) {
      try {
        final decoded = jsonDecode(storedOverrides) as Map<String, Object?>;
        _categoryLevels.clear();
        for (final entry in decoded.entries) {
          final value = LogLevel.values.asNameMap()[entry.value];
          if (value != null) _categoryLevels[entry.key] = value;
        }
      } on FormatException {
        // A corrupt overrides blob resets to defaults rather than failing
        // logging setup.
        _categoryLevels.clear();
      }
    }
    notifyListeners();
  }

  /// Sets the global minimum level.
  Future<void> setMinimumLevel(LogLevel level) async {
    if (level == _minimumLevel) return;
    _minimumLevel = level;
    _minimumLevelTouched = true;
    notifyListeners();
    await _store?.write(_minimumLevelKey, _levelName(level));
  }

  /// Sets (or, with `null`, removes) the override for [category].
  Future<void> setCategoryLevel(String category, LogLevel? level) async {
    if (level == null) {
      if (_categoryLevels.remove(category) == null) return;
    } else {
      if (_categoryLevels[category] == level) return;
      _categoryLevels[category] = level;
    }
    _categoryLevelsTouched = true;
    notifyListeners();
    await _persistOverrides();
  }

  /// Removes every category override.
  Future<void> clearCategoryLevels() async {
    if (_categoryLevels.isEmpty) return;
    _categoryLevels.clear();
    _categoryLevelsTouched = true;
    notifyListeners();
    await _persistOverrides();
  }

  /// The effective minimum level for [category].
  ///
  /// The longest matching override wins; overrides match the exact category
  /// or any dotted sub-category. Falls back to [minimumLevel].
  LogLevel levelFor(String category) {
    String? bestKey;
    for (final key in _categoryLevels.keys) {
      if (!_matches(key, category)) continue;
      if (bestKey == null || key.length > bestKey.length) bestKey = key;
    }
    return bestKey == null ? _minimumLevel : _categoryLevels[bestKey]!;
  }

  /// Whether an event at [level] in [category] should be logged.
  bool isEnabled(String category, LogLevel level) {
    if (level == LogLevel.none) return false;
    return level.value >= levelFor(category).value;
  }

  static bool _matches(String override, String category) {
    if (category == override) return true;
    return category.startsWith(override) &&
        category.length > override.length &&
        category[override.length] == '.';
  }

  Future<void> _persistOverrides() async {
    final store = _store;
    if (store == null) return;
    if (_categoryLevels.isEmpty) {
      await store.delete(_categoryLevelsKey);
      return;
    }
    await store.write(
      _categoryLevelsKey,
      jsonEncode(<String, String>{
        for (final entry in _categoryLevels.entries)
          entry.key: _levelName(entry.value),
      }),
    );
  }
}
