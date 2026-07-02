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

    test('ModelConfig round trips settings', () {
      const model = ModelConfig(
        id: 'm1',
        sourceId: 's1',
        modelId: 'gemma-local',
        displayName: 'Gemma',
        settings: {'llama.modelUrl': 'https://example.com/model.gguf'},
      );

      final restored = ModelConfig.fromJson(model.toJson());

      expect(restored.id, 'm1');
      expect(restored.displayName, 'Gemma');
      expect(restored.settings, {
        'llama.modelUrl': 'https://example.com/model.gguf',
      });
    });

    test('ProviderType round trips local llama and API-key requirements', () {
      expect(ProviderType.fromWireName('local_llama'), ProviderType.localLlama);
      expect(ProviderType.localLlama.requiresApiKey, isFalse);
      expect(ProviderType.openAiCompatible.requiresApiKey, isTrue);
      expect(ProviderType.anthropic.requiresApiKey, isTrue);
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
        access: AgentAccessConfig(
          enableWebSearch: false,
          enableLocation: true,
          enableWakeLock: true,
        ),
      );

      final restored = SavedAgentConfig.fromJson(agent.toJson());

      expect(restored.temperature, 0.4);
      expect(restored.maxOutputTokens, 256);
      expect(restored.instructions, 'be nice');
      expect(restored.access?.enableWebSearch, isFalse);
      expect(restored.access?.enableLocation, isTrue);
      expect(restored.access?.enableWakeLock, isTrue);
      expect(restored.access?.enableFileMemory, isTrue);
    });

    test('SavedAgentConfig keeps legacy access unset when absent', () {
      final restored = SavedAgentConfig.fromJson(const {
        'id': 'a1',
        'name': 'Helper',
        'modelId': 'm1',
      });

      expect(restored.access, isNull);
    });

    test('SavedAgentConfig round trips delegations', () {
      const agent = SavedAgentConfig(
        id: 'a1',
        name: 'Helper',
        modelId: 'm1',
        delegations: [
          AgentDelegationConfig(
            agentId: 'a2',
            instructions: 'Use for cost schedules.',
          ),
          AgentDelegationConfig(agentId: 'a3'),
        ],
      );

      final restored = SavedAgentConfig.fromJson(agent.toJson());

      expect(restored.delegations, hasLength(2));
      expect(restored.delegations[0].agentId, 'a2');
      expect(restored.delegations[0].instructions, 'Use for cost schedules.');
      expect(restored.delegations[1].agentId, 'a3');
      expect(restored.delegations[1].instructions, isEmpty);
    });

    test('SavedAgentConfig loads legacy JSON with no delegations', () {
      final restored = SavedAgentConfig.fromJson(const {
        'id': 'a1',
        'name': 'Helper',
        'modelId': 'm1',
      });

      expect(restored.delegations, isEmpty);
      expect(restored.toJson(), isNot(contains('delegations')));
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

    group('delegation integrity', () {
      Future<void> seedModel() async {
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
      }

      test('saveAgent rejects a delegate that does not exist', () async {
        await seedModel();

        await expectLater(
          manager.saveAgent(
            const SavedAgentConfig(
              id: 'a1',
              name: 'Helper',
              modelId: 'm1',
              delegations: [AgentDelegationConfig(agentId: 'missing')],
            ),
          ),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('saveAgent rejects self-delegation', () async {
        await seedModel();

        await expectLater(
          manager.saveAgent(
            const SavedAgentConfig(
              id: 'a1',
              name: 'Helper',
              modelId: 'm1',
              delegations: [AgentDelegationConfig(agentId: 'a1')],
            ),
          ),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('saveAgent rejects duplicate delegate ids', () async {
        await seedModel();
        await manager.saveAgent(
          const SavedAgentConfig(id: 'a2', name: 'Accounting', modelId: 'm1'),
        );

        await expectLater(
          manager.saveAgent(
            const SavedAgentConfig(
              id: 'a1',
              name: 'Helper',
              modelId: 'm1',
              delegations: [
                AgentDelegationConfig(agentId: 'a2'),
                AgentDelegationConfig(agentId: 'a2'),
              ],
            ),
          ),
          throwsA(isA<ConfiguredAgentException>()),
        );
      });

      test('deleteAgent blocks when the agent is a delegate', () async {
        await seedModel();
        await manager.saveAgent(
          const SavedAgentConfig(id: 'a2', name: 'Accounting', modelId: 'm1'),
        );
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a1',
            name: 'Helper',
            modelId: 'm1',
            delegations: [AgentDelegationConfig(agentId: 'a2')],
          ),
        );

        await expectLater(
          manager.deleteAgent('a2'),
          throwsA(isA<ConfiguredAgentException>()),
        );
        expect(await manager.agents.getAgent('a2'), isNotNull);
      });

      test('deleteAgent cascade strips references then deletes', () async {
        await seedModel();
        await manager.saveAgent(
          const SavedAgentConfig(id: 'a2', name: 'Accounting', modelId: 'm1'),
        );
        await manager.saveAgent(
          const SavedAgentConfig(id: 'a3', name: 'Research', modelId: 'm1'),
        );
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a1',
            name: 'Helper',
            modelId: 'm1',
            delegations: [
              AgentDelegationConfig(agentId: 'a2'),
              AgentDelegationConfig(agentId: 'a3', instructions: 'Research.'),
            ],
          ),
        );

        await manager.deleteAgent('a2', cascade: true);

        expect(await manager.agents.getAgent('a2'), isNull);
        final helper = await manager.agents.getAgent('a1');
        expect(helper?.delegations, hasLength(1));
        expect(helper?.delegations.single.agentId, 'a3');
      });

      test('deleteModel cascade strips delegation references', () async {
        await seedModel();
        await manager.saveModel(
          const ModelConfig(id: 'm2', sourceId: 's1', modelId: 'haiku'),
        );
        await manager.saveAgent(
          const SavedAgentConfig(id: 'a2', name: 'Accounting', modelId: 'm2'),
        );
        await manager.saveAgent(
          const SavedAgentConfig(
            id: 'a1',
            name: 'Helper',
            modelId: 'm1',
            delegations: [AgentDelegationConfig(agentId: 'a2')],
          ),
        );

        await manager.deleteModel('m2', cascade: true);

        expect(await manager.agents.getAgent('a2'), isNull);
        final helper = await manager.agents.getAgent('a1');
        expect(helper, isNotNull);
        expect(helper?.delegations, isEmpty);
      });
    });
  });
}
