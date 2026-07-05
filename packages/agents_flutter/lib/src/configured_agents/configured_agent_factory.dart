// ignore_for_file: prefer_initializing_formals

// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:a2a/a2a.dart' show A2AClient;
import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../chat_client_flutter_extensions.dart';
import '../flutter_harness_agent_options.dart';
import '../flutter_harness_service_collection_extensions.dart';
import 'agent_scope.dart';
import 'configured_agent_exception.dart';
import 'configured_agents_manager.dart';
import 'configured_chat_client_factory.dart';
import 'models/model_config.dart';
import 'models/model_source_config.dart';
import 'models/provider_type.dart';
import 'models/saved_agent_config.dart';

/// The author name stamped on loop-synthesized feedback messages injected
/// while a delegating agent waits for its background agents.
///
/// The messages reach the model (and the durable transcript) like any other
/// user-role message; UIs that display transcripts can skip messages carrying
/// this author name.
const String loopFeedbackAuthorName = 'background-task-loop';

/// The default per-response output-token cap for configured agents.
///
/// Configured agents can target arbitrary user-entered models, so this is more
/// conservative than the raw Flutter harness default. Users can still raise the
/// cap per saved agent or through harness configuration when their model
/// supports it.
const int defaultConfiguredAgentMaxOutputTokens = 4096;

/// Wires scope-dependent harness capabilities (chat history, file stores,
/// memory) onto [options] when an agent is built for a specific
/// conversation.
///
/// Called by [ConfiguredAgentFactory] after saved-agent access and
/// delegations are applied, so the callback sees the effective options.
typedef ConfigureHarnessForScope =
    void Function(
      SavedAgentConfig agent,
      FlutterHarnessAgentOptions options,
      AgentScope scope,
    );

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
    ConfigureHarnessForScope? configureHarnessForScope,
  }) : _chatClientFactory = chatClientFactory,
       _maxContextWindowTokens = maxContextWindowTokens,
       _maxOutputTokens = maxOutputTokens,
       _configureHarness = configureHarness,
       _configureHarnessForScope = configureHarnessForScope;

  final ConfiguredAgentsManager _manager;
  final ConfiguredChatClientFactory _chatClientFactory;
  final int _maxContextWindowTokens;
  final int _maxOutputTokens;
  final void Function(FlutterHarnessAgentOptions options)? _configureHarness;
  final ConfigureHarnessForScope? _configureHarnessForScope;

  /// Resolves the saved agent with [agentId].
  ///
  /// Supply [httpClient] to inject a fake transport in tests. Supply [scope]
  /// to wire conversation-scoped capabilities via the factory's
  /// [ConfigureHarnessForScope] callback.
  Future<AIAgent> createAgentById(
    String agentId, {
    http.Client? httpClient,
    AgentScope? scope,
  }) async {
    final agent = await _manager.agents.getAgent(agentId);
    if (agent == null) {
      throw ConfiguredAgentException('No saved agent with id "$agentId".');
    }
    return createAgent(agent, httpClient: httpClient, scope: scope);
  }

  /// Resolves [agent] into an [AIAgent].
  ///
  /// When [agent] has delegations, the delegate agents are built with their
  /// own model, instructions, and access settings and attached as background
  /// agents. Delegates themselves are built without delegation support, so
  /// nested (and cyclic) configured delegation is inert.
  ///
  /// Supply [httpClient] to inject a fake transport in tests. Supply [scope]
  /// to wire conversation-scoped capabilities via the factory's
  /// [ConfigureHarnessForScope] callback; delegates receive a child scope so
  /// their persisted state stays separate from the parent conversation.
  /// Additional delegates beyond the agent's saved delegations — for
  /// example the other participants of a group conversation — are supplied
  /// via [extraDelegations] and merged in (saved delegations win on
  /// conflicting agent ids).
  Future<AIAgent> createAgent(
    SavedAgentConfig agent, {
    http.Client? httpClient,
    AgentScope? scope,
    List<AgentDelegationConfig> extraDelegations = const [],
  }) => _createAgent(
    agent,
    httpClient: httpClient,
    includeDelegations: true,
    scope: scope,
    extraDelegations: extraDelegations,
  );

  Future<AIAgent> _createAgent(
    SavedAgentConfig agent, {
    required http.Client? httpClient,
    required bool includeDelegations,
    required AgentScope? scope,
    List<AgentDelegationConfig> extraDelegations = const [],
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

    if (source.providerType == ProviderType.network) {
      return _createNetworkAgent(agent, model, source, bearer: apiKey);
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
    final delegations = [
      ...agent.delegations,
      ...extraDelegations.where(
        (extra) =>
            !agent.delegations.any((saved) => saved.agentId == extra.agentId),
      ),
    ];
    final hasBackgroundAgents = includeDelegations && delegations.isNotEmpty;
    if (hasBackgroundAgents) {
      await _applyDelegations(options, agent, delegations, httpClient, scope);
    }
    if (scope != null) {
      _configureHarnessForScope?.call(agent, options, scope);
    }
    // Applied after the scope callback so the policy sees the scoped file
    // store when it has to rebuild the file access provider.
    ToolApprovalAgentOptions? toolApprovalOptions;
    if (access != null && access.enableFileAccess) {
      toolApprovalOptions = _applyFileAccessPolicy(options, access);
    }
    var effectiveMaxOutputTokens =
        agent.maxOutputTokens ??
        options.chatOptions?.maxOutputTokens ??
        _maxOutputTokens;
    // Local GGUF models have a real, small context window; the factory-wide
    // default (sized for hosted frontier models) would never trigger
    // compaction, letting long conversations overflow n_ctx and fail at the
    // native layer. Derive the harness budget from the model's configured
    // context size instead, and keep the output reservation within it.
    var maxContextWindowTokens = _maxContextWindowTokens;
    if (source.providerType == ProviderType.localLlama) {
      maxContextWindowTokens =
          int.tryParse(model.settings['llama.contextSize']?.trim() ?? '') ??
          8192;
      effectiveMaxOutputTokens = min(
        effectiveMaxOutputTokens,
        maxContextWindowTokens ~/ 4,
      );
    }
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

    AIAgent result = chatClient.asFlutterHarnessAgent(
      maxContextWindowTokens,
      effectiveMaxOutputTokens,
      options: options,
    );
    if (toolApprovalOptions != null) {
      result = ToolApprovalAgent(result, options: toolApprovalOptions);
    }
    if (hasBackgroundAgents) {
      // A delegating agent must not end its turn while delegate tasks are
      // still running: keep re-invoking it until the background agents
      // provider reports every task finished. The loop's synthesized
      // feedback messages carry a marker author name so UIs can filter them
      // out of displayed transcripts.
      result = LoopAgent(
        result,
        BackgroundTaskCompletionLoopEvaluator(),
        options: LoopAgentOptions()
          ..onBehalfOfAuthorName = loopFeedbackAuthorName
          ..excludeOnBehalfOfMessages = true,
      );
    }
    return result;
  }

  /// Applies the saved file access policy from [access] to [options].
  ///
  /// Read-only access replaces the harness-built file access provider with
  /// one whose write tools are disabled. Auto-approval modes move the
  /// tool-approval middleware out of the harness and return the
  /// [ToolApprovalAgentOptions] carrying the matching file access
  /// auto-approval rule; the factory then wraps the built agent in a
  /// [ToolApprovalAgent] configured with those options, since the harness
  /// does not expose its own middleware's options.
  ToolApprovalAgentOptions? _applyFileAccessPolicy(
    FlutterHarnessAgentOptions options,
    AgentAccessConfig access,
  ) {
    if (!access.enableFileWriteTools) {
      final store = options.fileAccessStore ?? InMemoryAgentFileStore();
      options
        ..disableFileAccess = true
        ..aiContextProviders = [
          ...?options.aiContextProviders,
          FileAccessProvider(
            store,
            options: FileAccessProviderOptions()..disableWriteTools = true,
          ),
        ];
    }

    final rule = switch (access.fileToolApprovalMode) {
      FileToolApprovalMode.alwaysAsk => null,
      FileToolApprovalMode.autoApproveReadOnly =>
        FileAccessProvider.readOnlyToolsAutoApprovalRule,
      FileToolApprovalMode.autoApproveAll =>
        FileAccessProvider.allToolsAutoApprovalRule,
    };
    if (rule == null || options.disableToolApproval) {
      return null;
    }

    options.disableToolApproval = true;
    return ToolApprovalAgentOptions()..autoApprovalRules = [rule];
  }

  /// Builds a remote A2A agent for a network source.
  ///
  /// The saved model's `modelId` is the agent's path on the paired host
  /// (for example `/agents/researcher`); the source endpoint is the host's
  /// base URL; the pairing bearer is stored where API keys live. Remote
  /// agents run inside the host's own harness, so local harness options,
  /// access toggles, and delegations do not apply.
  AIAgent _createNetworkAgent(
    SavedAgentConfig agent,
    ModelConfig model,
    ModelSourceConfig source, {
    required String? bearer,
  }) {
    final endpoint = source.endpoint;
    if (endpoint == null || endpoint.isEmpty) {
      throw ConfiguredAgentException(
        'Network source "${source.displayName}" has no endpoint. '
        'Re-pair with the host.',
      );
    }
    if (bearer == null || bearer.isEmpty) {
      throw ConfiguredAgentException(
        'No pairing credential is stored for "${source.displayName}". '
        'Re-pair with the host.',
      );
    }
    final baseUrl = endpoint.replaceAll(RegExp(r'/$'), '') + model.modelId;
    return A2AClient(
      baseUrl,
      customHeaders: {'authorization': 'Bearer $bearer'},
    ).asAIAgent(
      id: agent.id,
      name: agent.name,
      description: agent.description.isEmpty ? null : agent.description,
    );
  }

  /// Resolves [agent]'s delegations into background agents on [options].
  ///
  /// Overrides any callback-supplied background agents, consistent with how
  /// the factory overrides other saved-agent-owned option fields.
  Future<void> _applyDelegations(
    FlutterHarnessAgentOptions options,
    SavedAgentConfig agent,
    List<AgentDelegationConfig> delegations,
    http.Client? httpClient,
    AgentScope? scope,
  ) async {
    final delegates = <AIAgent>[];
    final guidanceByAgentName = <String, String>{};
    final seenNames = <String>{};
    for (final delegation in delegations) {
      if (delegation.agentId == agent.id) {
        throw ConfiguredAgentException(
          'Agent "${agent.name}" cannot delegate to itself.',
        );
      }
      final delegateConfig = await _manager.agents.getAgent(delegation.agentId);
      if (delegateConfig == null) {
        throw ConfiguredAgentException(
          'Agent "${agent.name}" delegates to an agent that no longer '
          'exists.',
        );
      }
      if (delegateConfig.name.trim().isEmpty) {
        throw ConfiguredAgentException(
          'Agent "${agent.name}" has a delegate with an empty name.',
        );
      }
      if (!seenNames.add(delegateConfig.name.toLowerCase())) {
        throw ConfiguredAgentException(
          'Agent "${agent.name}" has multiple delegates named '
          '"${delegateConfig.name}". Delegate names must be unique.',
        );
      }
      delegates.add(
        await _createAgent(
          delegateConfig,
          httpClient: httpClient,
          includeDelegations: false,
          scope: scope?.child('delegate-${delegateConfig.id}'),
        ),
      );
      if (delegation.instructions.trim().isNotEmpty) {
        guidanceByAgentName[delegateConfig.name] = delegation.instructions
            .trim();
      }
    }
    options
      ..backgroundAgents = delegates
      ..backgroundAgentsProviderOptions = (BackgroundAgentsProviderOptions()
        ..agentListBuilder = (agents) =>
            buildDelegateAgentListText(agents, guidanceByAgentName));
  }

  /// Builds the background-agent list text shown to a delegating agent,
  /// appending per-delegate guidance from [guidanceByAgentName] (matched
  /// case-insensitively by agent name).
  @visibleForTesting
  static String buildDelegateAgentListText(
    Map<String, AIAgent> agents,
    Map<String, String> guidanceByAgentName,
  ) {
    final guidance = {
      for (final entry in guidanceByAgentName.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final sb = StringBuffer()..writeln('Available background agents:');
    for (final entry in agents.entries) {
      sb.write('- ');
      sb.write(entry.key);
      final description = entry.value.description;
      if (description != null && description.trim().isNotEmpty) {
        sb.write(': ');
        sb.write(description);
      }
      sb.writeln();
      final agentGuidance = guidance[entry.key.toLowerCase()];
      if (agentGuidance != null) {
        sb.writeln('  Guidance: $agentGuidance');
      }
    }
    return sb.toString();
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
