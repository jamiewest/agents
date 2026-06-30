// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:http/http.dart' as http;

import 'configured_agent_exception.dart';
import 'configured_agents_manager.dart';
import 'configured_chat_client_factory.dart';
import 'models/saved_agent_config.dart';

/// Resolves a [SavedAgentConfig] into a runnable [AIAgent].
///
/// Pulls the agent's model, source, and API key from the
/// [ConfiguredAgentsManager], builds a chat client via
/// [ConfiguredChatClientFactory], and maps temperature/max-output-tokens onto
/// the agent's [ChatOptions]. Throws [ConfiguredAgentException] when any
/// required piece of configuration is missing.
class ConfiguredAgentFactory {
  /// Creates a [ConfiguredAgentFactory] over [manager].
  ConfiguredAgentFactory(
    this._manager, {
    ConfiguredChatClientFactory chatClientFactory =
        const ConfiguredChatClientFactory(),
  }) : _chatClientFactory = chatClientFactory;

  final ConfiguredAgentsManager _manager;
  final ConfiguredChatClientFactory _chatClientFactory;

  /// Resolves the saved agent with [agentId].
  ///
  /// Supply [httpClient] to inject a fake transport in tests.
  Future<AIAgent> createAgentById(
    String agentId, {
    http.Client? httpClient,
  }) async {
    final agent = await _manager.agents.getAgent(agentId);
    if (agent == null) {
      throw ConfiguredAgentException('No saved agent with id "$agentId".');
    }
    return createAgent(agent, httpClient: httpClient);
  }

  /// Resolves [agent] into an [AIAgent].
  ///
  /// Supply [httpClient] to inject a fake transport in tests.
  Future<AIAgent> createAgent(
    SavedAgentConfig agent, {
    http.Client? httpClient,
  }) async {
    final model = await _manager.sources.getModel(agent.modelId);
    if (model == null) {
      throw ConfiguredAgentException(
        'Agent "${agent.name}" references a model that no longer exists.',
      );
    }

    final source = await _manager.sources.getSource(model.sourceId);
    if (source == null) {
      throw ConfiguredAgentException(
        'Model "${model.label}" references a source that no longer exists.',
      );
    }

    final apiKey = await _manager.getSourceApiKey(source.id);
    if (apiKey == null || apiKey.isEmpty) {
      throw ConfiguredAgentException(
        'No API key is stored for source "${source.displayName}".',
      );
    }

    final chatClient = _chatClientFactory.createChatClient(
      source: source,
      model: model,
      apiKey: apiKey,
      httpClient: httpClient,
    );

    final options = ChatClientAgentOptions()
      ..name = agent.name
      ..description = agent.description.isEmpty ? null : agent.description
      ..chatOptions = ChatOptions(
        modelId: model.modelId,
        instructions: agent.instructions.isEmpty ? null : agent.instructions,
        temperature: agent.temperature,
        maxOutputTokens: agent.maxOutputTokens,
      );

    return chatClient.asAIAgent(options: options);
  }
}
