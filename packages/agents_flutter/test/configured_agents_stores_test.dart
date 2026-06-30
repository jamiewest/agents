// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('config model JSON', () {
    test('ModelSourceConfig round trips and omits secrets', () {
      const source = ModelSourceConfig(
        id: 's1',
        providerType: ProviderType.openAiCompatible,
        displayName: 'Local',
        endpoint: 'http://localhost:1234/v1',
        settings: {'org': 'acme'},
      );

      final restored = ModelSourceConfig.fromJson(source.toJson());

      expect(restored.id, 's1');
      expect(restored.providerType, ProviderType.openAiCompatible);
      expect(restored.displayName, 'Local');
      expect(restored.endpoint, 'http://localhost:1234/v1');
      expect(restored.settings, {'org': 'acme'});
      expect(source.toJson().toString(), isNot(contains('apiKey')));
    });

    test('SavedAgentConfig round trips with optional numbers', () {
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm1',
        description: 'desc',
        instructions: 'be nice',
        temperature: 0.4,
        maxOutputTokens: 256,
      );

      final restored = SavedAgentConfig.fromJson(agent.toJson());

      expect(restored.temperature, 0.4);
      expect(restored.maxOutputTokens, 256);
      expect(restored.instructions, 'be nice');
    });
  });

  group('ModelSourceStore', () {
    test('saves, lists, and removes sources and models', () async {
      final store = ModelSourceStore(InMemoryKeyValueStore());

      await store.saveSource(
        const ModelSourceConfig(
          id: 's1',
          providerType: ProviderType.anthropic,
          displayName: 'Anthropic',
        ),
      );
      await store.saveModel(
        const ModelConfig(id: 'm1', sourceId: 's1', modelId: 'claude'),
      );

      expect(await store.listSources(), hasLength(1));
      expect(await store.listModelsForSource('s1'), hasLength(1));

      await store.removeModel('m1');
      expect(await store.listModels(), isEmpty);
    });
  });

  group('ConfiguredAgentsManager', () {
    late InMemoryKeyValueStore kv;
    late InMemorySecretStore secrets;
    late ConfiguredAgentsManager manager;

    setUp(() {
      kv = InMemoryKeyValueStore();
      secrets = InMemorySecretStore();
      manager = ConfiguredAgentsManager(
        sources: ModelSourceStore(kv),
        agents: AgentConfigurationStore(kv),
        secrets: secrets,
      );
    });

    test('keeps API keys out of the public key/value store', () async {
      const source = ModelSourceConfig(
        id: 's1',
        providerType: ProviderType.anthropic,
        displayName: 'Anthropic',
      );

      await manager.saveSource(source, apiKey: 'sk-super-secret');

      // The secret is retrievable only through the secret store.
      expect(await manager.getSourceApiKey('s1'), 'sk-super-secret');

      // Nothing persisted in the non-secret store contains key material.
      for (final key in await kv.keys()) {
        final value = await kv.read(key);
        expect(value, isNot(contains('sk-super-secret')));
      }
    });

    test('blocks deleting a source that still has models', () async {
      await manager.saveSource(
        const ModelSourceConfig(
          id: 's1',
          providerType: ProviderType.anthropic,
          displayName: 'Anthropic',
        ),
        apiKey: 'sk-1',
      );
      await manager.saveModel(
        const ModelConfig(id: 'm1', sourceId: 's1', modelId: 'claude'),
      );

      await expectLater(
        manager.deleteSource('s1'),
        throwsA(isA<ConfiguredAgentException>()),
      );
      expect(await manager.sources.getSource('s1'), isNotNull);
    });

    test('cascade delete removes dependents and the secret', () async {
      await manager.saveSource(
        const ModelSourceConfig(
          id: 's1',
          providerType: ProviderType.anthropic,
          displayName: 'Anthropic',
        ),
        apiKey: 'sk-1',
      );
      await manager.saveModel(
        const ModelConfig(id: 'm1', sourceId: 's1', modelId: 'claude'),
      );
      await manager.saveAgent(
        const SavedAgentConfig(id: 'a1', name: 'Helper', modelId: 'm1'),
      );

      await manager.deleteSource('s1', cascade: true);

      expect(await manager.sources.listSources(), isEmpty);
      expect(await manager.sources.listModels(), isEmpty);
      expect(await manager.agents.listAgents(), isEmpty);
      expect(await manager.getSourceApiKey('s1'), isNull);
    });

    test('blocks deleting a model still used by an agent', () async {
      await manager.saveSource(
        const ModelSourceConfig(
          id: 's1',
          providerType: ProviderType.anthropic,
          displayName: 'Anthropic',
        ),
      );
      await manager.saveModel(
        const ModelConfig(id: 'm1', sourceId: 's1', modelId: 'claude'),
      );
      await manager.saveAgent(
        const SavedAgentConfig(id: 'a1', name: 'Helper', modelId: 'm1'),
      );

      await expectLater(
        manager.deleteModel('m1'),
        throwsA(isA<ConfiguredAgentException>()),
      );

      await manager.deleteModel('m1', cascade: true);
      expect(await manager.sources.listModels(), isEmpty);
      expect(await manager.agents.listAgents(), isEmpty);
    });

    test('clears a stored key when an empty key is set', () async {
      await manager.setSourceApiKey('s1', 'sk-1');
      expect(await manager.hasSourceApiKey('s1'), isTrue);

      await manager.setSourceApiKey('s1', '');
      expect(await manager.hasSourceApiKey('s1'), isFalse);
    });
  });
}
