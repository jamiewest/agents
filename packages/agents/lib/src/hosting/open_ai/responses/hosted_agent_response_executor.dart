// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/HostedAgentResponseExecutor.cs.
//
// Upstream resolves agents as keyed services from an IServiceProvider and
// shares event generation via a ToStreamingResponseAsync extension. This port
// resolves agents through a host-supplied callback (matching the router
// precedent in this module) and delegates execution to an
// [AIAgentResponseExecutor] over the resolved agent, which owns the
// streaming-event generation.

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/ai_agent.dart';
import '../open_ai_responses_map_options.dart';
import 'agent_invocation_context.dart';
import 'ai_agent_response_executor.dart';
import 'models/create_response.dart';
import 'models/response.dart';
import 'models/streaming_response_event.dart';
import 'open_ai_response_request_info_builder.dart';
import 'response_executor.dart';

/// Resolves a hosted [AIAgent] by name, returning `null` when unknown.
typedef ResolveHostedAgent = AIAgent? Function(String agentName);

/// A [ResponseExecutor] that routes requests to hosted agents based on
/// `agent.name` or `metadata["entity_id"]`.
///
/// The `model` field is reserved for actual model names and is never used
/// for entity/agent identification.
class HostedAgentResponseExecutor implements ResponseExecutor {
  /// Creates a [HostedAgentResponseExecutor] resolving agents via
  /// [resolveAgent].
  HostedAgentResponseExecutor(
    this._resolveAgent, {
    OpenAIResponsesMapOptions? mapOptions,
    LoggerFactory? loggerFactory,
  }) : _mapOptions = mapOptions ?? OpenAIResponsesMapOptions(),
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'HostedAgentResponseExecutor',
       );

  final ResolveHostedAgent _resolveAgent;
  final OpenAIResponsesMapOptions _mapOptions;
  final Logger _logger;

  @override
  Future<ResponseError?> validateRequest(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  }) async {
    final agentName = _agentName(request);

    if (agentName == null || agentName.isEmpty) {
      return ResponseError(
        code: 'missing_required_parameter',
        message:
            'No \'agent.name\' or \'metadata["entity_id"]\' specified in '
            'the request.',
      );
    }

    final agent = _resolveAgent(agentName);
    if (agent == null) {
      if (_logger.isEnabled(LogLevel.warning)) {
        _logger.logWarning("Failed to resolve agent with name '$agentName'");
      }

      return ResponseError(
        code: 'agent_not_found',
        message:
            "Agent '$agentName' not found. Ensure the agent is registered "
            "with '$agentName' name with the host.",
      );
    }

    // Surface unsupported request settings as a clean request error rather
    // than an unhandled exception during execution.
    try {
      _mapOptions.runOptionsFactory(request.toRequestInfo());
    } on UnsupportedError catch (e) {
      return ResponseError(
        code: 'unsupported_parameter',
        message: e.message ?? 'Unsupported request setting.',
      );
    }

    return null;
  }

  @override
  Stream<StreamingResponseEvent> execute(
    AgentInvocationContext context,
    CreateResponse request, {
    List<ChatMessage>? conversationHistory,
    CancellationToken? cancellationToken,
  }) {
    final agentName = _agentName(request);
    final agent = agentName == null ? null : _resolveAgent(agentName);
    if (agent == null) {
      throw StateError("Agent '${agentName ?? ''}' not found.");
    }

    return AIAgentResponseExecutor(agent, mapOptions: _mapOptions).execute(
      context,
      request,
      conversationHistory: conversationHistory,
      cancellationToken: cancellationToken,
    );
  }

  /// Extracts the agent name for a request from the `agent.name` property,
  /// falling back to `metadata["entity_id"]`.
  static String? _agentName(CreateResponse request) {
    final agentName = request.agent?.name;
    if (agentName != null && agentName.isNotEmpty) {
      return agentName;
    }
    return request.metadata?['entity_id'];
  }
}
