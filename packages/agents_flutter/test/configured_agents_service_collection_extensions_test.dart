// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart' show ChatClientAgent;
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = ModelSourceConfig(
  id: 's-openai',
  providerType: ProviderType.openAiCompatible,
  displayName: 'Local',
  endpoint: 'http://localhost:4321/v1',
);
const _model = ModelConfig(
  id: 'm-openai',
  sourceId: 's-openai',
  modelId: 'gpt-test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('addConfiguredAgents', () {
    test('resolves the manager and factory as singletons', () {
      // Arrange.
      final services = ServiceCollection()
        ..addConfiguredAgents(
          keyValueStore: (_) => InMemoryKeyValueStore(),
          secretStore: (_) => InMemorySecretStore(),
        );
      final provider = services.buildServiceProvider();

      // Act.
      final manager = provider.getRequiredService<ConfiguredAgentsManager>();
      final factory = provider.getRequiredService<ConfiguredAgentFactory>();

      // Assert.
      expect(manager, isA<ConfiguredAgentsManager>());
      expect(factory, isA<ConfiguredAgentFactory>());
      expect(
        identical(
          manager,
          provider.getRequiredService<ConfiguredAgentsManager>(),
        ),
        isTrue,
      );
    });

    test('honors the in-memory store overrides', () {
      // Arrange.
      final keyValueStore = InMemoryKeyValueStore();
      final secretStore = InMemorySecretStore();
      final services = ServiceCollection()
        ..addConfiguredAgents(
          keyValueStore: (_) => keyValueStore,
          secretStore: (_) => secretStore,
        );
      final provider = services.buildServiceProvider();

      // Act & Assert: the overrides are the resolved instances.
      expect(
        identical(provider.getRequiredService<KeyValueStore>(), keyValueStore),
        isTrue,
      );
      expect(
        identical(provider.getRequiredService<SecretStore>(), secretStore),
        isTrue,
      );
    });

    test('manager persists through the injected key-value store', () async {
      // Arrange.
      final keyValueStore = InMemoryKeyValueStore();
      final services = ServiceCollection()
        ..addConfiguredAgents(
          keyValueStore: (_) => keyValueStore,
          secretStore: (_) => InMemorySecretStore(),
        );
      final provider = services.buildServiceProvider();
      final manager = provider.getRequiredService<ConfiguredAgentsManager>();

      // Act.
      await manager.saveAgent(
        const SavedAgentConfig(id: 'a1', name: 'A', modelId: 'm1'),
      );
      final agents = await manager.agents.listAgents();

      // Assert.
      expect(agents.single.id, 'a1');
      // The write landed in the injected store, not a real SharedPreferences.
      expect(await keyValueStore.keys(), isNotEmpty);
    });

    test('preserves an earlier KeyValueStore registration', () {
      // Arrange: a store registered before addConfiguredAgents should win,
      // because the extension uses tryAddSingleton.
      final preexisting = InMemoryKeyValueStore();
      final services = ServiceCollection()
        ..addSingleton<KeyValueStore>((_) => preexisting)
        ..addConfiguredAgents(
          keyValueStore: (_) => InMemoryKeyValueStore(),
          secretStore: (_) => InMemorySecretStore(),
        );
      final provider = services.buildServiceProvider();

      // Assert.
      expect(
        identical(provider.getRequiredService<KeyValueStore>(), preexisting),
        isTrue,
      );
    });

    test('passes harness configuration to resolved factories', () async {
      // Arrange.
      final services = ServiceCollection()
        ..addConfiguredAgents(
          configureHarness: (options) => options.enableWakeLock = true,
          keyValueStore: (_) => InMemoryKeyValueStore(),
          secretStore: (_) => InMemorySecretStore(),
        );
      final provider = services.buildServiceProvider();
      final manager = provider.getRequiredService<ConfiguredAgentsManager>();
      await manager.saveSource(_source, apiKey: 'sk-openai');
      await manager.saveModel(_model);
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm-openai',
      );
      await manager.saveAgent(agent);

      // Act.
      final built = await provider
          .getRequiredService<ConfiguredAgentFactory>()
          .createAgent(agent);
      final chatOptions = built.getServiceOf<ChatOptions>()!;
      final providerTypes = built
          .getServiceOf<ChatClientAgent>()!
          .aiContextProviders!
          .map((contextProvider) => contextProvider.runtimeType)
          .toList();
      final toolNames = chatOptions.tools!.map((tool) => tool.name).toList();

      // Assert.
      expect(providerTypes, contains(ConnectivityContextProvider));
      expect(toolNames, contains('set_wake_lock'));
      expect(toolNames, contains('get_connectivity'));
    });
  });
}
