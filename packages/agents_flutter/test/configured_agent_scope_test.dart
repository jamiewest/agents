// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart' show ChatHistoryProvider;
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _localSource = ModelSourceConfig(
  id: 's-local',
  providerType: ProviderType.localLlama,
  displayName: 'Local llama',
);
const _localModel = ModelConfig(
  id: 'm-local',
  sourceId: 's-local',
  modelId: 'local-gemma',
  settings: {'llama.modelUrl': 'https://example.com/model.gguf'},
);

ChatClient _staticEchoResolver({
  required ModelSourceConfig source,
  required ModelConfig model,
  http.Client? httpClient,
}) => _EchoChatClient();

final class _EchoChatClient extends ChatClient {
  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async => ChatResponse(
    messages: <ChatMessage>[ChatMessage.fromText(ChatRole.assistant, 'ok')],
  );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) => Stream<ChatResponseUpdate>.value(
    ChatResponseUpdate.fromText(ChatRole.assistant, 'ok'),
  );

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfiguredAgentFactory scope', () {
    late ConfiguredAgentsManager manager;

    setUp(() async {
      final kv = InMemoryKeyValueStore();
      manager = ConfiguredAgentsManager(
        sources: ModelSourceStore(kv),
        agents: AgentConfigurationStore(kv),
        secrets: InMemorySecretStore(),
      );
      await manager.saveSource(_localSource);
      await manager.saveModel(_localModel);
    });

    ConfiguredAgentFactory factory(ConfigureHarnessForScope onScope) =>
        ConfiguredAgentFactory(
          manager,
          chatClientFactory: const ConfiguredChatClientFactory(
            customClientResolver: _staticEchoResolver,
          ),
          configureHarnessForScope: onScope,
        );

    AgentScope scope({String conversationId = 'c1'}) => AgentScope(
      conversationId: conversationId,
      sessionIdResolver: () => 's1',
    );

    test('invokes the scope configurator with agent and scope', () async {
      const agent = SavedAgentConfig(id: 'a1', name: 'A', modelId: 'm-local');
      await manager.saveAgent(agent);
      final calls = <(String agentId, String conversationId)>[];

      await factory(
        (agent, options, scope) => calls.add((agent.id, scope.conversationId)),
      ).createAgent(agent, scope: scope());

      expect(calls, [('a1', 'c1')]);
    });

    test('does not invoke the scope configurator without a scope', () async {
      const agent = SavedAgentConfig(id: 'a1', name: 'A', modelId: 'm-local');
      await manager.saveAgent(agent);
      var called = false;

      await factory((_, _, _) => called = true).createAgent(agent);

      expect(called, isFalse);
    });

    test('a chat history provider set by the configurator is used', () async {
      const agent = SavedAgentConfig(id: 'a1', name: 'A', modelId: 'm-local');
      await manager.saveAgent(agent);
      final store = InMemoryRecordStore();
      FlutterChatHistoryProvider? installed;

      final built = await factory((agent, options, scope) {
        installed = FlutterChatHistoryProvider(
          store,
          conversationId: scope.conversationId,
          sessionIdResolver: scope.sessionIdResolver,
          senderAgentId: agent.id,
        );
        options.chatHistoryProvider = installed;
      }).createAgent(agent, scope: scope());

      expect(built.getServiceOf<ChatHistoryProvider>(), same(installed));
    });

    test('delegates receive a derived child scope', () async {
      const delegate = SavedAgentConfig(
        id: 'a2',
        name: 'Helper',
        modelId: 'm-local',
      );
      const lead = SavedAgentConfig(
        id: 'a1',
        name: 'Lead',
        modelId: 'm-local',
        delegations: [AgentDelegationConfig(agentId: 'a2')],
      );
      await manager.saveAgent(delegate);
      await manager.saveAgent(lead);
      final conversationIdsByAgent = <String, String>{};

      await factory((agent, options, scope) {
        conversationIdsByAgent[agent.id] = scope.conversationId;
      }).createAgent(lead, scope: scope());

      expect(conversationIdsByAgent['a1'], 'c1');
      expect(conversationIdsByAgent['a2'], 'c1#delegate-a2');
    });

    test('extraDelegations attach as delegates without saved config', () async {
      const teammate = SavedAgentConfig(
        id: 'a3',
        name: 'Teammate',
        modelId: 'm-local',
      );
      const lead = SavedAgentConfig(id: 'a1', name: 'Lead', modelId: 'm-local');
      await manager.saveAgent(teammate);
      await manager.saveAgent(lead);
      final scopedAgents = <String>[];

      await factory((agent, options, scope) {
        scopedAgents.add(agent.id);
      }).createAgent(
        lead,
        scope: scope(),
        extraDelegations: const [AgentDelegationConfig(agentId: 'a3')],
      );

      expect(scopedAgents, containsAll(['a1', 'a3']));
    });
  });
}
