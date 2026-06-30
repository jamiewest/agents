// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:extensions_flutter/extensions_flutter.dart';

import 'agent_configuration_store.dart';
import 'configured_agent_factory.dart';
import 'configured_agents_manager.dart';
import 'model_source_store.dart';
import 'storage/flutter_secure_secret_store.dart';
import 'storage/key_value_store.dart';
import 'storage/secret_store.dart';
import 'storage/shared_preferences_key_value_store.dart';

/// Registers the runtime-configurable agents stack into a [ServiceCollection].
extension ConfiguredAgentsServiceCollectionExtensions on ServiceCollection {
  /// Registers the configured-agents stores, manager, and factory.
  ///
  /// All services are registered with `tryAddSingleton`, so any instance
  /// registered earlier — including a test fake [KeyValueStore] or
  /// [SecretStore] — is preserved.
  ///
  /// By default the [KeyValueStore] is a [SharedPreferencesKeyValueStore] and
  /// the [SecretStore] is a [FlutterSecureSecretStore]. Supply [keyValueStore]
  /// or [secretStore] to override either — for example, with an in-memory
  /// store in tests or on platforms where the defaults are unavailable.
  ServiceCollection addConfiguredAgents({
    KeyValueStore Function(ServiceProvider sp)? keyValueStore,
    SecretStore Function(ServiceProvider sp)? secretStore,
  }) {
    tryAddSingleton<KeyValueStore>(
      (sp) => keyValueStore?.call(sp) ?? SharedPreferencesKeyValueStore(),
    );
    tryAddSingleton<SecretStore>(
      (sp) => secretStore?.call(sp) ?? FlutterSecureSecretStore(),
    );
    tryAddSingleton<ModelSourceStore>(
      (sp) => ModelSourceStore(sp.getRequiredService<KeyValueStore>()),
    );
    tryAddSingleton<AgentConfigurationStore>(
      (sp) => AgentConfigurationStore(sp.getRequiredService<KeyValueStore>()),
    );
    tryAddSingleton<ConfiguredAgentsManager>(
      (sp) => ConfiguredAgentsManager(
        sources: sp.getRequiredService<ModelSourceStore>(),
        agents: sp.getRequiredService<AgentConfigurationStore>(),
        secrets: sp.getRequiredService<SecretStore>(),
      ),
    );
    tryAddSingleton<ConfiguredAgentFactory>(
      (sp) =>
          ConfiguredAgentFactory(sp.getRequiredService<ConfiguredAgentsManager>()),
    );
    return this;
  }
}

/// Registers the runtime-configurable agents stack from a [FlutterBuilder].
extension ConfiguredAgentsFlutterBuilderExtensions on FlutterBuilder {
  /// Registers the configured-agents stores, manager, and factory.
  ///
  /// Designed for use inside `addFlutter`:
  ///
  /// ```dart
  /// services.addFlutter((flutter) {
  ///   flutter.useFlutterHarnessAgent();
  ///   flutter.useConfiguredAgents();
  ///   flutter.runApp((services) => const MyApp());
  /// });
  /// ```
  ///
  /// Delegates to
  /// [ConfiguredAgentsServiceCollectionExtensions.addConfiguredAgents].
  FlutterBuilder useConfiguredAgents({
    KeyValueStore Function(ServiceProvider sp)? keyValueStore,
    SecretStore Function(ServiceProvider sp)? secretStore,
  }) {
    services.addConfiguredAgents(
      keyValueStore: keyValueStore,
      secretStore: secretStore,
    );
    return this;
  }
}
