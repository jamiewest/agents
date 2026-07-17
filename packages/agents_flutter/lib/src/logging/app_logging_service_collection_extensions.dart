// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions_flutter/extensions_flutter.dart';

import '../configured_agents/storage/key_value_store.dart';
import '../configured_agents/storage/shared_preferences_key_value_store.dart';
import 'app_log_store.dart';
import 'app_log_store_logger_provider.dart';
import 'logging_settings.dart';

/// Registers the in-app logging pipeline into a [ServiceCollection].
extension AppLoggingServiceCollectionExtensions on ServiceCollection {
  /// Registers an [AppLogStore], [LoggingSettings], and a log provider that
  /// captures every `Logger` event for in-app viewing.
  ///
  /// Also installs a dynamic filter rule so [LoggingSettings] governs every
  /// registered provider (including the host's debug-console provider) at
  /// log time: level changes made in a settings UI apply immediately, and
  /// categories below `trace` skip trace-payload rendering entirely.
  ///
  /// [defaultLevel] is the global minimum until the user changes it. The
  /// persisted values load at host startup through a hosted service using
  /// the registered [KeyValueStore] (a [SharedPreferencesKeyValueStore] is
  /// registered as a fallback, matching `addConfiguredAgents`).
  ///
  /// Supply [capacity] to change how many records the store retains.
  ///
  /// Calling this twice on one collection is a no-op the second time;
  /// otherwise two stores and two filter rules would be installed.
  ServiceCollection addAppLogging({
    LogLevel defaultLevel = LogLevel.information,
    int capacity = 2000,
  }) {
    if (any((descriptor) => descriptor.serviceType == AppLogStore)) {
      return this;
    }

    final store = AppLogStore(capacity: capacity);
    final settings = LoggingSettings(defaultLevel: defaultLevel);

    tryAddSingleton<KeyValueStore>((_) => SharedPreferencesKeyValueStore());
    // Registered with addSingleton (not tryAdd) so the instances the filter
    // rule and provider capture are the same ones DI hands out.
    addSingleton<AppLogStore>((_) => store);
    addSingleton<LoggingSettings>((_) => settings);
    addSingleton<LoggerProvider>((_) => AppLogStoreLoggerProvider(store));

    // The rule's delegate runs on every `log`/`isEnabled` call, which is
    // what makes the settings live without rebuilding the logger factory.
    configure<LoggerFilterOptions>(LoggerFilterOptions.new, (options) {
      options.minLevel = LogLevel.trace;
      options.rules.add(
        LoggerFilterRule(
          null,
          null,
          null,
          (provider, category, level) =>
              settings.isEnabled(category, level ?? LogLevel.information),
        ),
      );
    });

    addHostedService<LoggingSettingsLoader>(
      (sp) => LoggingSettingsLoader(
        settings: sp.getRequiredService<LoggingSettings>(),
        keyValueStore: sp.getRequiredService<KeyValueStore>(),
      ),
    );
    return this;
  }
}

/// Registers the in-app logging pipeline from a [FlutterBuilder].
extension AppLoggingFlutterBuilderExtensions on FlutterBuilder {
  /// Registers the in-app logging pipeline.
  ///
  /// Designed for use inside `addFlutter`:
  ///
  /// ```dart
  /// services.addFlutter((flutter) {
  ///   flutter.useAppLogging();
  ///   flutter.runApp((services) => const MyApp());
  /// });
  /// ```
  ///
  /// Delegates to
  /// [AppLoggingServiceCollectionExtensions.addAppLogging].
  FlutterBuilder useAppLogging({
    LogLevel defaultLevel = LogLevel.information,
    int capacity = 2000,
  }) {
    services.addAppLogging(defaultLevel: defaultLevel, capacity: capacity);
    return this;
  }
}

/// Loads persisted [LoggingSettings] once the host starts.
///
/// Runs as a [BackgroundService] so the async [KeyValueStore] read happens
/// off the logging hot path; until it completes the in-memory defaults
/// apply.
final class LoggingSettingsLoader extends BackgroundService {
  /// Creates a loader that binds [settings] to [keyValueStore].
  LoggingSettingsLoader({required this.settings, required this.keyValueStore});

  /// The settings instance consulted by the log filter.
  final LoggingSettings settings;

  /// The store holding the persisted level configuration.
  final KeyValueStore keyValueStore;

  @override
  Future<void> execute(CancellationToken stoppingToken) =>
      settings.bindStore(keyValueStore);
}
