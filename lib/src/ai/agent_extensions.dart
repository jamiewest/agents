import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import 'ai_agent_builder.dart';

/// Provides extensions for [AIAgent].
extension AIAgentExtensions on AIAgent {
  /// Creates a new [AIAgentBuilder] using this agent as the pipeline root.
  AIAgentBuilder asBuilder() => AIAgentBuilder(innerAgent: this);

  /// Creates an [AIFunction] that runs this [AIAgent].
  ///
  /// The resulting function accepts a `query` string and returns the agent's
  /// response text. If [session] is supplied, all function invocations reuse
  /// that session, matching the stateful C# helper behavior.
  AIFunction asAIFunction({
    AIFunctionFactoryOptions? options,
    AgentSession? session,
  }) {
    final functionName = options?.name ?? _sanitizeAgentName(name);
    final functionDescription =
        options?.description ??
        description ??
        'Invoke an agent to retrieve some information.';

    return AIFunctionFactory.create(
      name: functionName,
      description: functionDescription,
      parametersSchema: const {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Input query to invoke the agent.',
          },
        },
        'required': ['query'],
      },
      callback: (arguments, {CancellationToken? cancellationToken}) async {
        final query =
            (arguments['query'] ?? arguments['input'] ?? arguments['message'])
                ?.toString() ??
            '';
        final response = await run(
          session,
          AgentRunOptions(),
          cancellationToken: cancellationToken,
          message: query,
        );
        return response.text;
      },
    );
  }
}

String _sanitizeAgentName(String? agentName) {
  final value = agentName?.trim();
  if (value == null || value.isEmpty) {
    return 'agent';
  }
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  final collapsed = sanitized.replaceAll(RegExp(r'_+'), '_');
  final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  if (trimmed.isEmpty) {
    return 'agent';
  }
  return RegExp(r'^[A-Za-z_]').hasMatch(trimmed) ? trimmed : 'agent_$trimmed';
}
