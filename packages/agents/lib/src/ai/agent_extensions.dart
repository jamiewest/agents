import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import 'ai_agent_builder.dart';
import 'chat_client/ai_agent_chat_client.dart';
import 'chat_client/chat_client_agent.dart';
import 'chat_client/per_service_call_chat_history_persisting_chat_client.dart';

/// Provides extensions for [AIAgent].
extension AIAgentExtensions on AIAgent {
  /// Creates a new [AIAgentBuilder] using this agent as the pipeline root.
  AIAgentBuilder asBuilder() => AIAgentBuilder(innerAgent: this);

  /// Creates a [ChatClient] that delegates its operations to this [AIAgent].
  ///
  /// By default the returned client is stateless: no [AgentSession] is used,
  /// so every call must supply the full conversation history, just as when
  /// calling a [ChatClient] directly. Such a client reports no conversation
  /// id on its responses and accepts none; an id carried by the agent's raw
  /// response or streamed update is cleared on a copy rather than forwarded,
  /// and a non-blank [ChatOptions.conversationId] supplied by the caller is
  /// rejected. Only the conversation id is withheld; every other member of
  /// the response passes through as the agent produced it.
  ///
  /// When [session] is supplied the returned client is stateful. The session
  /// stores the history, which is exactly what a non-null
  /// [ChatResponse.conversationId] signals under the [ChatClient] contract,
  /// so the client reports one on every response. Callers should follow it:
  /// send only the new messages on each subsequent call, along with the
  /// reported id, rather than resending a history the session is already
  /// accumulating. The reported id is [conversationId], or a generated one
  /// when that is omitted, and it never changes for the life of the client.
  /// Echoing it back is accepted; any other non-blank id is rejected, and a
  /// blank one is treated as absent. Service-side conversation ids are not
  /// surfaced in this mode: a response carrying one is re-stamped with the
  /// client's id.
  ///
  /// So that the conversation id is reported even when there is nothing else
  /// to report, a session-bound stream that produces no updates still yields
  /// a single update carrying only that id.
  ///
  /// A session-bound client supports one in-flight request at a time.
  /// Concurrent calls over the same bound session race on its history state,
  /// which is not synchronized, so the caller must serialize them.
  ///
  /// [allowNonChatClientAgents] defaults to `false`, which restricts this
  /// method to agents whose behavior behind a [ChatClient] is well defined:
  /// the agent must be a [ChatClientAgent], or return one from an unkeyed
  /// service request. Passing `true` wraps any agent anyway and accepts the
  /// consequences: such an agent is not known to understand
  /// `ChatClientAgentRunOptions`, so of any [ChatOptions] supplied to the
  /// returned client only [ChatOptions.responseFormat] can be relied on to
  /// take effect; every other member, [ChatOptions.tools] included, is
  /// silently ignored.
  ///
  /// Throws an [ArgumentError] when [conversationId] is supplied without a
  /// [session], is blank, or is a framework-reserved value, and a
  /// [StateError] when [allowNonChatClientAgents] is `false` and this agent
  /// is not (and does not expose) a [ChatClientAgent].
  ChatClient asChatClient({
    AgentSession? session,
    String? conversationId,
    bool allowNonChatClientAgents = false,
  }) {
    if (conversationId != null) {
      if (session == null) {
        // Without a session the caller owns the history, so there is no
        // stored conversation for an id to name.
        throw ArgumentError.value(
          conversationId,
          'conversationId',
          'A conversation id is only meaningful for a session-bound client, '
              'so it may not be supplied without a session.',
        );
      }

      if (conversationId.trim().isEmpty) {
        // A blank id is reported verbatim on every response, where callers
        // that test it for emptiness read it as "no stored history" and
        // resend the full history the session already has.
        throw ArgumentError.value(
          conversationId,
          'conversationId',
          'Must not be empty or whitespace.',
        );
      }

      if (conversationId == localHistoryConversationId) {
        // The framework stamps this value to mark history as handled in
        // process. Reporting it as this client's conversation id would make
        // an internal marker indistinguishable from a real conversation.
        throw ArgumentError.value(
          conversationId,
          'conversationId',
          'Reserved for internal use and cannot be used as a '
              'client-supplied conversation id.',
        );
      }
    }

    // The probe asks for ChatClientAgent rather than ChatClient because the
    // adapter's value rests on the agent honoring ChatClientAgentRunOptions,
    // which is a ChatClientAgent capability rather than a chat client one.
    // The flag is evaluated first so that an opted-in call never issues a
    // service request against the agent.
    if (!allowNonChatClientAgents && getServiceOf<ChatClientAgent>() == null) {
      throw StateError(
        "The agent of type '$runtimeType' is not a ChatClientAgent and does "
        'not expose one through getService, so every ChatOptions member '
        'except ChatOptions.responseFormat is liable to be silently ignored '
        'by the returned ChatClient. To wrap this agent anyway, accepting '
        'the limitations documented on asChatClient, pass '
        'allowNonChatClientAgents: true.',
      );
    }

    return AIAgentChatClient(this, session, conversationId);
  }

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
