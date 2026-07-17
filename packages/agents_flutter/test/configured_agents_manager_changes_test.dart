// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = ModelSourceConfig(
  id: 's1',
  providerType: ProviderType.localLlama,
  displayName: 'Local',
);

const _model = ModelConfig(id: 'm1', sourceId: 's1', modelId: 'gemma');

const _agent = SavedAgentConfig(id: 'a1', name: 'Helper', modelId: 'm1');

ConfiguredAgentsManager _buildManager() => ConfiguredAgentsManager(
  sources: ModelSourceStore(InMemoryKeyValueStore()),
  agents: AgentConfigurationStore(InMemoryKeyValueStore()),
  secrets: InMemorySecretStore(),
);

void main() {
  group('ConfiguredAgentsManager.configurationChanges', () {
    late ConfiguredAgentsManager manager;
    late List<void> events;

    setUp(() {
      manager = _buildManager();
      events = [];
      manager.configurationChanges.listen(events.add);
    });

    test('emits once per successful save', () async {
      await manager.saveSource(_source);
      await manager.saveModel(_model);
      await manager.saveAgent(_agent);
      await pumpEventQueue();

      expect(events, hasLength(3));
    });

    test('emits for deletions', () async {
      await manager.saveSource(_source);
      await manager.saveModel(_model);
      await manager.saveAgent(_agent);
      await pumpEventQueue();
      events.clear();

      await manager.deleteAgent('a1');
      await pumpEventQueue();
      expect(events, hasLength(1));

      await manager.deleteModel('m1');
      await pumpEventQueue();
      expect(events, hasLength(2));

      await manager.deleteSource('s1');
      await pumpEventQueue();
      expect(events, hasLength(3));
    });

    test('emits for cascade deletions', () async {
      await manager.saveSource(_source);
      await manager.saveModel(_model);
      await manager.saveAgent(_agent);
      await pumpEventQueue();
      events.clear();

      // Removes the model and the dependent agent in one operation.
      await manager.deleteSource('s1', cascade: true);
      await pumpEventQueue();

      expect(events, isNotEmpty);
      expect(await manager.agents.listAgents(), isEmpty);
      expect(await manager.sources.listModels(), isEmpty);
    });

    test('does not emit when a save fails validation', () async {
      await manager.saveSource(_source);
      await manager.saveModel(_model);
      await pumpEventQueue();
      events.clear();

      const invalid = SavedAgentConfig(
        id: 'a2',
        name: 'Broken',
        modelId: 'm1',
        delegations: [AgentDelegationConfig(agentId: 'does-not-exist')],
      );
      await expectLater(
        manager.saveAgent(invalid),
        throwsA(isA<ConfiguredAgentException>()),
      );
      await pumpEventQueue();

      expect(events, isEmpty);
    });

    test('does not emit when a blocked delete fails', () async {
      await manager.saveSource(_source);
      await manager.saveModel(_model);
      await manager.saveAgent(_agent);
      await pumpEventQueue();
      events.clear();

      await expectLater(
        manager.deleteModel('m1'),
        throwsA(isA<ConfiguredAgentException>()),
      );
      await expectLater(
        manager.deleteSource('s1'),
        throwsA(isA<ConfiguredAgentException>()),
      );
      await pumpEventQueue();

      expect(events, isEmpty);
    });

    test('agentChanges keeps its per-agent meaning', () async {
      final agentIds = <String>[];
      manager.agentChanges.listen(agentIds.add);

      await manager.saveSource(_source);
      await manager.saveModel(_model);
      await pumpEventQueue();
      expect(agentIds, isEmpty, reason: 'source/model saves are not agents');

      await manager.saveAgent(_agent);
      await pumpEventQueue();
      expect(agentIds, ['a1']);
    });

    test('dispose closes the stream', () async {
      await manager.dispose();
      expect(manager.configurationChanges, emitsDone);
    });
  });

  group('ConfiguredAgentsManager.saveSource', () {
    test('stores the API key before notifying listeners', () async {
      final manager = ConfiguredAgentsManager(
        sources: ModelSourceStore(InMemoryKeyValueStore()),
        agents: AgentConfigurationStore(InMemoryKeyValueStore()),
        secrets: _SlowWriteSecretStore(),
      );
      String? keyAtNotification;
      manager.configurationChanges.listen((_) {
        // Reads run as soon as the notification lands, mirroring listeners
        // that rebuild an agent (and read its key) on configuration changes.
        unawaited(
          manager.getSourceApiKey('s1').then((k) => keyAtNotification ??= k),
        );
      });

      await manager.saveSource(_source, apiKey: 'sk-test');
      await pumpEventQueue();

      expect(keyAtNotification, 'sk-test');
    });
  });
}

/// A secret store whose writes land a few microtasks late, exposing
/// notify-before-write races deterministically.
final class _SlowWriteSecretStore implements SecretStore {
  final InMemorySecretStore _inner = InMemorySecretStore();

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    await pumpEventQueue(times: 3);
    await _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);
}
