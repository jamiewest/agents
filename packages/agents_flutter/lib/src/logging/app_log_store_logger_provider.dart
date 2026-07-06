// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions/logging.dart';
import 'package:extensions/system.dart' show Disposable;

import 'app_log_record.dart';
import 'app_log_store.dart';

/// A [LoggerProvider] that writes every log event into an [AppLogStore].
///
/// Filtering is not done here: the app logging registration installs a
/// factory-level filter rule (driven by `LoggingSettings`), so events that
/// reach this provider have already passed the user's configured levels.
class AppLogStoreLoggerProvider implements LoggerProvider {
  /// Creates a provider that records into [store].
  AppLogStoreLoggerProvider(this.store);

  /// The store that receives every log event.
  final AppLogStore store;

  @override
  Logger createLogger(String categoryName) =>
      _AppLogStoreLogger(store, categoryName);

  @override
  void dispose() {}
}

class _AppLogStoreLogger implements Logger {
  _AppLogStoreLogger(this._store, this._category);

  final AppLogStore _store;
  final String _category;

  @override
  bool isEnabled(LogLevel logLevel) => logLevel != LogLevel.none;

  @override
  void log<TState>({
    required LogLevel logLevel,
    required EventId eventId,
    required TState state,
    Object? error,
    required LogFormatter<TState> formatter,
  }) {
    if (!isEnabled(logLevel)) return;
    final message = formatter(state, error);
    if (message.isEmpty && error == null) return;
    _store.add(
      AppLogRecord(
        timestamp: DateTime.now(),
        level: logLevel,
        category: _category,
        message: message,
        error: error,
      ),
    );
  }

  @override
  Disposable? beginScope<TState>(TState state) => NullScope.instance;
}
