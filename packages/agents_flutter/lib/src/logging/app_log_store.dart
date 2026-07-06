// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'app_log_record.dart';

/// A bounded, observable buffer of recent log events.
///
/// Every `Logger` created through the app log provider writes here, giving
/// in-app log viewers a single live feed across the whole application. The
/// buffer keeps the most recent [capacity] records so a long session cannot
/// grow memory without bound.
class AppLogStore extends ChangeNotifier {
  /// Creates a store that retains at most [capacity] records.
  AppLogStore({this.capacity = 2000})
    : assert(capacity > 0, 'capacity must be positive');

  /// The maximum number of records retained.
  final int capacity;

  final List<AppLogRecord> _records = <AppLogRecord>[];
  final SplayTreeSet<String> _categories = SplayTreeSet<String>();

  /// The retained records, oldest first.
  ///
  /// This is a live unmodifiable view, not a snapshot: log viewers read it
  /// on every rebuild — once per captured record while visible — so copying
  /// up to [capacity] entries per read would dominate the cost of logging.
  List<AppLogRecord> get records =>
      UnmodifiableListView<AppLogRecord>(_records);

  /// Every category seen since the store was created (or last cleared),
  /// sorted alphabetically.
  ///
  /// A live unmodifiable view, like [records].
  ///
  /// Categories persist across [clear] of individual records only when they
  /// log again; clearing empties this set too so stale categories do not
  /// linger in filter menus.
  Set<String> get categories => UnmodifiableSetView<String>(_categories);

  /// Appends [record], evicting the oldest record when full.
  void add(AppLogRecord record) {
    _records.add(record);
    if (_records.length > capacity) {
      _records.removeRange(0, _records.length - capacity);
    }
    _categories.add(record.category);
    notifyListeners();
  }

  /// Removes all records and known categories.
  void clear() {
    if (_records.isEmpty && _categories.isEmpty) return;
    _records.clear();
    _categories.clear();
    notifyListeners();
  }
}
