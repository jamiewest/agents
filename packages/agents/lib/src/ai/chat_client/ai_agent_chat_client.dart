import 'dart:async';
import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_response_extensions.dart';
import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_agent.dart';
import '../../abstractions/ai_agent_metadata.dart';
import 'chat_client_agent_run_options.dart';

/// A [ChatClient] that delegates all of its operations to an [AIAgent].
///
/// This adapter is the inverse of `ChatClientAgent`: rather than building an
/// agent on top of a chat client, it exposes an existing agent to any
/// component that consumes the [ChatClient] abstraction. The contract it
/// presents — what it reports, what it accepts and what it rejects, in both
/// stateless and session-bound mode — is documented on
/// `AIAgentExtensions.asChatClient`, the only entry point through which this
/// type is constructed.
///
/// The invariant everything else serves is that every conversation id this
/// adapter reports is one it accepts back. A bound adapter therefore reports
/// a single fixed id rather than anything derived from the response, the
/// session or the service, and, when the caller supplies none, mints it per
/// instance, so a generated id handed out by an adapter bound to one session
/// cannot be replayed against an adapter bound to another.
///
/// The same invariant is why a stateless adapter clears ids instead of
/// forwarding them: a caller that round-trips a reported id would otherwise
/// be rejected on its next turn.
///
/// Nothing is rewritten in place. Responses and updates belong to the inner
/// agent and callers rely on getting them back as they were, so an id is
/// stamped or cleared on a copy and the inner instance travels on only when
/// there is nothing to change.
class AIAgentChatClient implements ChatClient {
  /// Creates an adapter over [agent].
  ///
  /// [session] is used for every request; when `null` the adapter is
  /// stateless and the caller supplies the full history on each call.
  /// [conversationId] is the one id reported on every response when a session
  /// is bound; when omitted an id unique to this instance is generated. It is
  /// ignored without a session, since a stateless adapter names no
  /// conversation.
  ///
  /// The arguments are validated by `AIAgentExtensions.asChatClient`, the
  /// intended entry point.
  AIAgentChatClient(this._agent, this._session, String? conversationId)
    // No session means no stored history and so nothing to name; an id is
    // only minted for the bound case.
    : _conversationId = _session == null
          ? null
          : (conversationId ?? _generateConversationId());

  final AIAgent _agent;
  final AgentSession? _session;

  /// The one conversation id this adapter ever reports, or `null` when it is
  /// stateless and therefore has no conversation to name.
  ///
  /// Deliberately per instance rather than a shared constant: a constant
  /// would let an adapter bound to one session accept an id minted by an
  /// adapter bound to a different session.
  final String? _conversationId;

  ChatClientMetadata? _metadata;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final resolved = _resolveRequestOptions(options);

    final response = (await _agent.run(
      _session,
      _toAgentRunOptions(resolved),
      messages: messages,
      cancellationToken: cancellationToken,
    )).asChatResponse();

    // The reported id is always this adapter's own: the single bound id, or
    // none at all when stateless. Applying it means a copy, because the
    // response belongs to the inner agent. Only when there is nothing to
    // change is the instance returned as it stands.
    return _conversationId == null && response.conversationId == null
        ? response
        : _cloneWithConversationId(response, _conversationId);
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    // Resolved eagerly so that a rejected conversation id surfaces from the
    // call rather than when the returned stream is listened to.
    final resolved = _resolveRequestOptions(options);
    return _getStreamingResponseCore(messages, resolved, cancellationToken);
  }

  Stream<ChatResponseUpdate> _getStreamingResponseCore(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  ) async* {
    var yieldedAnyUpdate = false;

    await for (final update in _agent.runStreaming(
      _session,
      _toAgentRunOptions(options),
      messages: messages,
      cancellationToken: cancellationToken,
    )) {
      final converted = update.asChatResponseUpdate();
      yieldedAnyUpdate = true;

      if (_conversationId == null && converted.conversationId == null) {
        // Nothing to change, so the converted instance travels on as it
        // stands.
        yield converted;
      } else {
        // Bound mode stamps its single id, stateless mode clears whatever the
        // update arrived with. Either way the change lands on a copy.
        yield converted.clone()..conversationId = _conversationId;
      }
    }

    final trailingConversationId = _conversationId;
    if (!yieldedAnyUpdate && trailingConversationId != null) {
      // A bound run that produced nothing would otherwise aggregate to a null
      // conversation id, which under the ChatClient contract means "no stored
      // history" and invites the caller to resend everything into a session
      // that is already accumulating it. One id-only update repairs the
      // aggregate.
      yield ChatResponseUpdate()..conversationId = trailingConversationId;
    }
  }

  @override
  T? getService<T>({Object? key}) {
    if (key == null && this is T) {
      return this as T;
    }

    final service = _agent.getService(T, serviceKey: key);
    if (service is T) {
      return service;
    }

    if (key == null && T == ChatClientMetadata) {
      _metadata ??= ChatClientMetadata(
        providerName: (_agent.getService(AIAgentMetadata) as AIAgentMetadata?)
            ?.providerName,
      );
      return _metadata as T;
    }

    return null;
  }

  /// Disposing the adapter has no effect: it does not own the lifetime of the
  /// underlying [AIAgent] or [AgentSession], so it is safe to call any number
  /// of times.
  @override
  void dispose() {
    // Intentionally a no-op.
  }

  /// Interprets the [ChatOptions.conversationId] a caller supplied and
  /// produces the options to forward to the agent.
  ///
  /// The rule either mode enforces is the same one: the adapter never accepts
  /// an id it did not hand out. A bound adapter hands out exactly one, so the
  /// check is a single comparison; a stateless adapter hands out none, so
  /// every non-blank id is rejected — forwarding one would let an untrusted
  /// caller name a service-side conversation of its choosing and have the
  /// agent read and extend it under the host's credentials.
  ///
  /// A blank id is read as an absent one and cleared before the agent sees
  /// it: transports routinely materialize an omitted field as an empty
  /// string, and the id this adapter hands out is never blank.
  ///
  /// Throws a [StateError] when a bound adapter is given a non-blank
  /// conversation id other than the one it reports, or a stateless adapter is
  /// given a non-blank conversation id at all.
  ChatOptions? _resolveRequestOptions(ChatOptions? options) {
    final incomingId = options?.conversationId;
    if (options == null || incomingId == null) {
      return options;
    }

    if (incomingId.trim().isEmpty) {
      // Blank names no conversation, and forwarding it as it stands is not
      // neutral: downstream blankness checks would read a whitespace id as
      // naming a service-managed conversation.
      return _withoutConversationId(options);
    }

    final conversationId = _conversationId;
    if (conversationId == null) {
      throw StateError(
        "The supplied ChatOptions.conversationId '$incomingId' cannot be "
        'used: this asChatClient client is not bound to a session, so it has '
        'no conversation to continue and does not accept a conversation id. '
        'Send the full history on every call, or bind a session with '
        'agent.asChatClient(session: session); to continue an existing '
        'service conversation, bind a session obtained from '
        'ChatClientAgent.createSession(conversationId).',
      );
    }

    if (incomingId == conversationId) {
      // The caller is echoing the id this adapter reported. Removing it
      // restores the as-if-absent semantics of the first turn, which the
      // bound session interprets as "continue".
      return _withoutConversationId(options);
    }

    // Only the caller's own value is named. The accepted id is a live
    // conversation identifier and this message may reach an untrusted caller
    // through a host, so disclosing it would turn the error into an oracle.
    throw StateError(
      "The supplied ChatOptions.conversationId '$incomingId' is not a known "
      'conversation id for this asChatClient client. Send back the '
      'conversation id from the most recent response, or omit it to continue '
      'the bound conversation. To converse over a different existing service '
      'conversation, bind the client to a session obtained from '
      'ChatClientAgent.createSession(conversationId).',
    );
  }

  /// Creates a copy of [options] carrying no conversation id.
  ///
  /// The caller owns the instance it supplied and may reuse it across calls,
  /// so an id is removed on a copy rather than in place.
  static ChatOptions _withoutConversationId(ChatOptions options) =>
      options.clone()..conversationId = null;

  /// Creates a copy of [response] carrying [conversationId].
  ///
  /// The response belongs to the inner agent, and callers rely on getting
  /// that instance back unmodified, so the id is never stamped in place.
  /// Reference-type members, [ChatResponse.rawRepresentation] included, are
  /// shared rather than duplicated so that everything reachable from the
  /// original stays reachable from the copy.
  static ChatResponse _cloneWithConversationId(
    ChatResponse response,
    String? conversationId,
  ) => ChatResponse(messages: response.messages)
    ..additionalProperties = response.additionalProperties
    ..continuationToken = response.continuationToken
    ..conversationId = conversationId
    ..createdAt = response.createdAt
    ..finishReason = response.finishReason
    ..modelId = response.modelId
    ..rawRepresentation = response.rawRepresentation
    ..responseId = response.responseId
    ..usage = response.usage;

  /// Converts [options] into the agent run options understood by agents that
  /// support chat options.
  ///
  /// [ChatOptions.responseFormat] is additionally surfaced on the base
  /// `AgentRunOptions` so that agents which do not understand
  /// [ChatClientAgentRunOptions] can still honor it. It is deliberately the
  /// only option copied to the base type: background responses require a
  /// session and continuation tokens that do not round-trip through the
  /// [ChatClient] abstraction, and additional properties carry agent-specific
  /// semantics a caller supplying [ChatOptions] is not expressing.
  static ChatClientAgentRunOptions? _toAgentRunOptions(ChatOptions? options) =>
      options == null
      ? null
      : (ChatClientAgentRunOptions(chatOptions: options)
          ..responseFormat = options.responseFormat);

  static final Random _random = Random.secure();

  static String _generateConversationId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
