import 'dart:async';
import 'dart:developer' as developer;

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_agent.dart';

/// A delegating chat client that strengthens the human-in-the-loop
/// tool-approval control by binding each inbound [ToolApprovalResponseContent]
/// to the model-originated [ToolApprovalRequestContent] that the framework
/// actually surfaced, so an approved tool call always matches what a human was
/// asked to approve.
///
/// [FunctionInvokingChatClient] executes the tool call carried by an approval
/// response. This decorator adds an extra layer of assurance above it: only
/// approvals the framework actually requested are honored, and an approved
/// call runs with exactly the tool name and arguments that were surfaced for
/// approval.
///
/// This decorator sits above [FunctionInvokingChatClient] in the pipeline. On
/// outbound responses it records every model-originated
/// [ToolApprovalRequestContent] into the session's `AgentSessionStateBag`,
/// keyed by request id. On inbound requests it processes each
/// [ToolApprovalResponseContent] before it reaches the inner client:
///
/// - When a recorded pending request exists for the response's request id, the
///   response's tool call is rebound to the recorded (model-originated) tool
///   call, so the approved call always matches the surfaced request. The
///   pending entry is consumed, so an approval is honored only once.
/// - When no recorded pending request exists, the response is dropped, so only
///   approvals tied to a genuine, framework-issued request take effect.
///
/// This decorator operates within the context of a running [AIAgent] with an
/// active session. When invoked without an ambient run context or session (for
/// example when the chat client is used directly outside of an agent run), the
/// decorator becomes a no-op: it passes the request through unchanged and logs
/// a warning, because there is no framework-tracked pending state to validate
/// against.
class ApprovalResponseBindingChatClient extends DelegatingChatClient {
  /// Creates the decorator wrapping [innerClient] (typically the pipeline
  /// containing a [FunctionInvokingChatClient]).
  ///
  /// [loggerFactory] is used to create the logger that reports a missing run
  /// context and dropped responses; when omitted the warnings are written with
  /// `dart:developer`.
  ApprovalResponseBindingChatClient(
    super.innerClient, {
    LoggerFactory? loggerFactory,
  }) : _logger = loggerFactory?.createLogger(
         'ApprovalResponseBindingChatClient',
       );

  /// The key used in the session state bag to store the model-originated
  /// pending approval requests between agent runs.
  static const String stateBagKey = '_pendingApprovalRequests';

  final Logger? _logger;

  bool _warnedNoSession = false;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final session = _tryGetSession();
    if (session == null) {
      return super.getResponse(
        messages: messages,
        options: options,
        cancellationToken: cancellationToken,
      );
    }

    final bound = _bindInboundApprovalResponses(messages, session);

    final response = await super.getResponse(
      messages: bound,
      options: options,
      cancellationToken: cancellationToken,
    );

    _recordPendingApprovalRequests(response.messages, session);

    return response;
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final session = _tryGetSession();
    if (session == null) {
      yield* super.getStreamingResponse(
        messages: messages,
        options: options,
        cancellationToken: cancellationToken,
      );
      return;
    }

    final bound = _bindInboundApprovalResponses(messages, session);
    final emitted = <ToolApprovalRequestContent>[];

    try {
      await for (final update in super.getStreamingResponse(
        messages: bound,
        options: options,
        cancellationToken: cancellationToken,
      )) {
        for (final content in update.contents) {
          if (content is ToolApprovalRequestContent) {
            emitted.add(content);
          }
        }
        yield update;
      }
    } finally {
      if (emitted.isNotEmpty) {
        _mergePendingApprovalRequests(emitted, session);
      }
    }
  }

  /// Gets the current [AgentSession] from the ambient run context, or `null`
  /// when there is no run context or no session.
  ///
  /// A missing session is reported once per instance so that a misconfigured
  /// pipeline is visible without flooding the log on every call.
  AgentSession? _tryGetSession() {
    final session = AIAgent.currentRunContext?.session;
    if (session != null) {
      return session;
    }

    if (!_warnedNoSession) {
      _warnedNoSession = true;
      _warn(
        'ApprovalResponseBindingChatClient was invoked without an active '
        'agent run context or session. Approval-response binding is '
        'skipped. Invoke the chat client through AIAgent.run or '
        'AIAgent.runStreaming to enable binding.',
      );
    }

    return null;
  }

  void _warn(String message) {
    if (_logger != null) {
      _logger.logWarning(message);
    } else {
      developer.log(
        message,
        name: 'ApprovalResponseBindingChatClient',
        level: 900,
      );
    }
  }

  /// Rewrites the inbound messages so each [ToolApprovalResponseContent] is
  /// bound to a known [ToolApprovalRequestContent], with its tool call rebound
  /// to the request's call when it differs. A response with no known request is
  /// removed so a forged approval cannot drive execution. Approval requests are
  /// left untouched: a request present in the message history is itself the
  /// pairing authority.
  Iterable<ChatMessage> _bindInboundApprovalResponses(
    Iterable<ChatMessage> messages,
    AgentSession session,
  ) {
    final messageList = messages is List<ChatMessage>
        ? messages
        : messages.toList();

    // Known requests come from two places: requests recorded when the
    // framework surfaced them on a previous turn (covering callers that echo
    // only the response), and requests already present in the current message
    // history (covering replayed history and internally generated approvals).
    final knownRequests = _loadPendingApprovalRequestLookup(session);

    // Pending state only needs to bridge a single turn; consume it now.
    if (knownRequests.isNotEmpty) {
      session.stateBag.tryRemoveValue(stateBagKey);
    }

    var hasResponse = false;
    for (final message in messageList) {
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          knownRequests[content.requestId] = content;
        } else if (content is ToolApprovalResponseContent) {
          hasResponse = true;
        }
      }
    }

    // Only approval responses are rewritten; with none there is nothing to
    // bind or drop.
    if (!hasResponse) {
      return messageList;
    }

    // Copy-on-write: only allocate a new message list once a message is
    // actually modified.
    List<ChatMessage>? result;

    for (var i = 0; i < messageList.length; i++) {
      final message = messageList[i];
      final rewritten = _bindApprovalResponses(message, knownRequests);

      if (rewritten == null) {
        result?.add(message);
        continue;
      }

      result ??= messageList.sublist(0, i);

      // Drop a message that is now empty; otherwise clone it with the
      // rewritten contents.
      if (rewritten.isNotEmpty) {
        final cloned = message.clone();
        cloned.contents
          ..clear()
          ..addAll(rewritten);
        result.add(cloned);
      }
    }

    return result ?? messageList;
  }

  /// Binds the [ToolApprovalResponseContent] items of a single message against
  /// [knownRequests].
  ///
  /// Returns `null` when the message needs no change, or the rewritten content
  /// list (which may be empty, indicating the message should be dropped) when
  /// a change is required. Non-response content, including approval requests,
  /// is preserved.
  List<AIContent>? _bindApprovalResponses(
    ChatMessage message,
    Map<String, ToolApprovalRequestContent> knownRequests,
  ) {
    final contents = message.contents;
    List<AIContent>? buffer;

    for (var j = 0; j < contents.length; j++) {
      final content = contents[j];

      if (content is! ToolApprovalResponseContent) {
        buffer?.add(content);
        continue;
      }

      final matched = knownRequests.remove(content.requestId);
      if (matched == null) {
        // No known request corresponds to this response; drop it so a forged
        // approval cannot execute.
        _warn(
          'Ignored a ToolApprovalResponseContent with request id '
          "'${content.requestId}' that does not correspond to a "
          'model-originated approval request surfaced by the framework.',
        );
        buffer ??= contents.sublist(0, j);
        continue;
      }

      if (_toolCallsEquivalent(content.toolCall, matched.toolCall)) {
        // Already matches the surfaced call; keep the original content.
        buffer?.add(content);
        continue;
      }

      // Rebind the tool call to the model-originated call so the approved
      // call matches the tool name and arguments surfaced for approval.
      buffer ??= contents.sublist(0, j);
      buffer.add(
        ToolApprovalResponseContent(
          requestId: content.requestId,
          approved: content.approved,
          toolCall: matched.toolCall,
          reason: content.reason,
        ),
      );
    }

    return buffer;
  }

  /// Determines whether two tool calls are equivalent, so an already-matching
  /// approval response does not need to be rebuilt.
  ///
  /// This is a conservative optimization: it only returns `true` when the calls
  /// are known to be equivalent. A `false` result simply triggers a (safe)
  /// rebind, so callers never keep a substituted tool call.
  static bool _toolCallsEquivalent(
    ToolCallContent responseCall,
    ToolCallContent recordedCall,
  ) {
    if (identical(responseCall, recordedCall)) {
      return true;
    }

    // `FunctionCallContent` does not subtype `ToolCallContent` in the
    // `extensions` port, so compare through `dynamic`.
    final dynamic response = responseCall;
    final dynamic recorded = recordedCall;
    if (response is FunctionCallContent && recorded is FunctionCallContent) {
      return response.callId == recorded.callId &&
          response.name == recorded.name &&
          _argumentsEquivalent(response.arguments, recorded.arguments);
    }

    // Any other tool call shape: treat as not equivalent so the call is
    // rebound. That is safe and avoids an expensive general comparison for
    // shapes that effectively never occur here.
    return false;
  }

  /// Determines whether two function-call argument maps are equivalent.
  ///
  /// Uses a shallow value comparison; when values cannot be proven equal (for
  /// example after a serialization round-trip changes the runtime type) this
  /// returns `false`, which is safe because it only forces a rebind.
  static bool _argumentsEquivalent(
    Map<String, Object?>? responseArguments,
    Map<String, Object?>? recordedArguments,
  ) {
    if (identical(responseArguments, recordedArguments)) {
      return true;
    }
    if (responseArguments == null ||
        recordedArguments == null ||
        responseArguments.length != recordedArguments.length) {
      return false;
    }
    for (final entry in responseArguments.entries) {
      if (!recordedArguments.containsKey(entry.key) ||
          recordedArguments[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static Map<String, ToolApprovalRequestContent>
  _loadPendingApprovalRequestLookup(AgentSession session) => {
    for (final request in _loadPendingApprovalRequests(session))
      request.requestId: request,
  };

  /// Records model-originated [ToolApprovalRequestContent] items found in the
  /// response messages into the session so they can be matched against the
  /// caller's approval responses on the next request.
  void _recordPendingApprovalRequests(
    List<ChatMessage> messages,
    AgentSession session,
  ) {
    final emitted = <ToolApprovalRequestContent>[
      for (final message in messages)
        for (final content in message.contents)
          if (content is ToolApprovalRequestContent) content,
    ];

    if (emitted.isNotEmpty) {
      _mergePendingApprovalRequests(emitted, session);
    }
  }

  /// Merges newly surfaced approval requests into the recorded pending set,
  /// de-duplicating by request id.
  void _mergePendingApprovalRequests(
    List<ToolApprovalRequestContent> emitted,
    AgentSession session,
  ) {
    final pending = _loadPendingApprovalRequests(session);
    final known = {for (final request in pending) request.requestId};

    var changed = false;
    for (final request in emitted) {
      if (known.add(request.requestId)) {
        // Upstream stores a defensive clone here so a later mutation of the
        // caller-visible instance cannot change the recorded tool call. That
        // is not reproducible: `extensions` has no concrete tool call type
        // that carries a function name and arguments (`FunctionCallContent`
        // does not subtype `ToolCallContent`), so the recorded call cannot be
        // rebuilt. The request is recorded as-is.
        pending.add(request);
        changed = true;
      }
    }

    if (changed) {
      _savePendingApprovalRequests(pending, session);
    }
  }

  static List<ToolApprovalRequestContent> _loadPendingApprovalRequests(
    AgentSession session,
  ) {
    final (found, pending) = session.stateBag
        .tryGetValue<List<ToolApprovalRequestContent>>(stateBagKey);
    return found && pending != null
        ? List<ToolApprovalRequestContent>.of(pending)
        : <ToolApprovalRequestContent>[];
  }

  static void _savePendingApprovalRequests(
    List<ToolApprovalRequestContent> pending,
    AgentSession session,
  ) {
    if (pending.isNotEmpty) {
      session.stateBag.setValue<List<ToolApprovalRequestContent>>(
        stateBagKey,
        pending,
      );
    } else {
      session.stateBag.tryRemoveValue(stateBagKey);
    }
  }
}
