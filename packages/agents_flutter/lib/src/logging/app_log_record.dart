// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions/logging.dart';
import 'package:flutter/foundation.dart';

/// One captured log event: what was logged, by which category, and when.
///
/// Records are produced by the in-app log provider and held in an
/// `AppLogStore` so log viewers can render, filter, and copy them without
/// attaching a debugger.
@immutable
class AppLogRecord {
  /// Creates a log record.
  const AppLogRecord({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.error,
  });

  /// When the event was logged.
  final DateTime timestamp;

  /// The severity of the event.
  final LogLevel level;

  /// The logger category that produced the event, e.g. `Agents.Traffic`.
  final String category;

  /// The formatted log message.
  final String message;

  /// The error attached to the event, if any.
  final Object? error;
}
