// ignore_for_file: prefer_initializing_formals

// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:http/http.dart' as http;

import '../chat_client_flutter_extensions.dart';
import '../flutter_harness_agent_options.dart';
import '../flutter_harness_service_collection_extensions.dart';
import 'configured_agent_exception.dart';
import 'configured_agents_manager.dart';
import 'configured_chat_client_factory.dart';
import 'models/saved_agent_config.dart';

/// The default per-response output-token cap for configured agents.
///
/// Configured agents can target arbitrary user-entered models, so this is more
/// conservative than the raw Flutter harness default. Users can still raise the
/// cap per saved agent or through harness configuration when their model
/// supports it.
const int defaultConfiguredAgentMaxOutputTokens = 4096;

/// Resolves a [SavedAgentConfig] into a runnable [AIAgent].
///
/// Pulls the agent's model, source, and API key from the
/// [ConfiguredAgentsManager], builds a chat client via
/// [ConfiguredChatClientFactory], and maps temperature/max-output-tokens onto
/// a full Flutter harness agent. Throws [ConfiguredAgentException] when any
/// required piece of configuration is missing.
class ConfiguredAgentFactory {
  /// Creates a [ConfiguredAgentFactory] over [manager].
  ConfiguredAgentFactory(
    this._manager, {
    ConfiguredChatClientFactory chatClientFactory =
        const ConfiguredChatClientFactory(),
    int maxContextWindowTokens = defaultFlutterHarnessMaxContextWindowTokens,
    int maxOutputTokens = defaultConfiguredAgentMaxOutputTokens,
    void Function(FlutterHarnessAgentOptions options)? configureHarness,
  }) : _chatClientFactory = chatClientFactory,
       _maxContextWindowTokens = maxContextWindowTokens,
       _maxOutputTokens = maxOutputTokens,
       _configureHarness = configureHarness;

  final ConfiguredAgentsManager _manager;
  final ConfiguredChatClientFactory _chatClientFactory;
  final int _maxContextWindowTokens;
  final int _maxOutputTokens;
  final void Function(FlutterHarnessAgentOptions options)? _configureHarness;

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
    if (source.providerType.requiresApiKey &&
        (apiKey == null || apiKey.isEmpty)) {
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

    final options = FlutterHarnessAgentOptions();
    _configureHarness?.call(options);
    final access = agent.access;
    if (access != null) {
      _applyAgentAccess(options, access);
    }
    final effectiveMaxOutputTokens =
        agent.maxOutputTokens ??
        options.chatOptions?.maxOutputTokens ??
        _maxOutputTokens;
    options
      ..id = agent.id
      ..name = agent.name
      ..description = agent.description.isEmpty ? null : agent.description
      ..chatOptions = _buildChatOptions(
        options.chatOptions,
        modelId: model.modelId,
        instructions: agent.instructions.isEmpty ? null : agent.instructions,
        temperature: agent.temperature,
        maxOutputTokens: effectiveMaxOutputTokens,
      );

    return chatClient.asFlutterHarnessAgent(
      _maxContextWindowTokens,
      effectiveMaxOutputTokens,
      options: options,
    );
  }

  ChatOptions _buildChatOptions(
    ChatOptions? configured, {
    required String modelId,
    required String? instructions,
    required double? temperature,
    required int? maxOutputTokens,
  }) {
    final chatOptions = configured?.clone() ?? ChatOptions();
    return chatOptions
      ..modelId = modelId
      ..instructions = instructions
      ..temperature = temperature
      ..maxOutputTokens = maxOutputTokens;
  }

  void _applyAgentAccess(
    FlutterHarnessAgentOptions options,
    AgentAccessConfig access,
  ) {
    options
      ..disableFileMemory = !access.enableFileMemory
      ..disableFileAccess = !access.enableFileAccess
      ..disableWebSearch = !access.enableWebSearch
      ..disableTodoProvider = !access.enableTodoList
      ..disableAgentModeProvider = !access.enableAgentMode
      ..disableAgentSkillsProvider = !access.enableSkills
      ..enableTemporal = access.enableTemporal
      ..enableConnectivity = access.enableConnectivity
      ..enableAppInfo = access.enableAppInfo
      ..enableDeviceInfo = access.enableDeviceInfo
      ..enableLocation = access.enableLocation
      ..enableNetworkInfo = access.enableNetworkInfo
      ..enableWakeLock = access.enableWakeLock;
  }
}
