import 'dart:async';
import 'dart:developer' as developer;

import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_agent.dart';

/// A delegating chat client that automatically removes
/// [ToolApprovalRequestContent] for tools that do not actually require
/// approval, storing auto-approved results in the session for transparent
/// re-injection on the next request.
///
/// [FunctionInvokingChatClient] has an all-or-nothing behavior for approvals:
/// when any tool in a response is an [ApprovalRequiredAIFunction], it converts
/// all [FunctionCallContent] items to [ToolApprovalRequestContent] — even for
/// tools that do not require approval. This decorator sits above
/// [FunctionInvokingChatClient] in the pipeline and transparently handles the
/// non-approval-required items so callers only see approval requests for
/// tools that truly need them.
///
/// On outbound responses, the decorator identifies
/// [ToolApprovalRequestContent] items for tools that are not wrapped in
/// [ApprovalRequiredAIFunction], removes them from the response, and stores
/// them in the session's `AgentSessionStateBag`. On the next inbound request,
/// the stored items are re-injected as pre-approved
/// [ToolApprovalResponseContent] so that [FunctionInvokingChatClient] can
/// process them alongside the caller's human-approved responses.
///
/// This decorator operates within the context of a running [AIAgent] with an
/// active session. When invoked without an ambient run context or session
/// (for example when the chat client is used directly outside of an agent
/// run), the decorator becomes a no-op: it passes the request through
/// unchanged and logs a warning, because there is no session in which to
/// stash the bypassed requests.
class ApprovalNotRequiredFunctionBypassingChatClient
    extends DelegatingChatClient {
  /// Creates the decorator wrapping [innerClient] (typically a
  /// [FunctionInvokingChatClient]).
  ///
  /// [loggerFactory] is used to create the logger that reports a missing run
  /// context; when omitted the warning is written with `dart:developer`.
  ApprovalNotRequiredFunctionBypassingChatClient(
    super.innerClient, {
    LoggerFactory? loggerFactory,
  }) : _logger = loggerFactory?.createLogger(
         'ApprovalNotRequiredFunctionBypassingChatClient',
       );

  /// The key used in the session state bag to store pending auto-approved
  /// function calls between agent runs.
  static const String stateBagKey = '_autoApprovedFunctionCalls';

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

    final autoApprovableNames = _getAutoApprovableToolNames(options);

    final withApprovals = _injectPendingAutoApprovals(messages, session);

    final response = await super.getResponse(
      messages: withApprovals,
      options: options,
      cancellationToken: cancellationToken,
    );

    _removeAutoApprovedFromMessages(
      response.messages,
      autoApprovableNames,
      session,
    );

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

    final autoApprovableNames = _getAutoApprovableToolNames(options);

    final withApprovals = _injectPendingAutoApprovals(messages, session);
    final autoApproved = <ToolApprovalRequestContent>[];

    try {
      await for (final update in super.getStreamingResponse(
        messages: withApprovals,
        options: options,
        cancellationToken: cancellationToken,
      )) {
        if (_filterUpdateContents(update, autoApprovableNames, autoApproved)) {
          yield update;
        }
      }
    } finally {
      if (autoApproved.isNotEmpty) {
        session.stateBag.setValue<List<ToolApprovalRequestContent>>(
          stateBagKey,
          autoApproved,
        );
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
      const message =
          'ApprovalNotRequiredFunctionBypassingChatClient was invoked '
          'without an active agent run context or session. Bypassing is '
          'skipped and every approval request is surfaced to the caller. '
          'Invoke the chat client through AIAgent.run or '
          'AIAgent.runStreaming to enable bypassing.';
      if (_logger != null) {
        _logger.logWarning(message);
      } else {
        developer.log(
          message,
          name: 'ApprovalNotRequiredFunctionBypassingChatClient',
          level: 900,
        );
      }
    }

    return null;
  }

  /// Checks the session for stored auto-approvals from a previous turn and
  /// injects them as a user message containing [ToolApprovalResponseContent]
  /// items appended to the input messages.
  ///
  /// All stored requests are unconditionally injected as approved responses
  /// regardless of whether the tool set has changed, because the LLM requires
  /// a complete set of tool call responses for a prior turn.
  static Iterable<ChatMessage> _injectPendingAutoApprovals(
    Iterable<ChatMessage> messages,
    AgentSession session,
  ) {
    final (found, pendingRequests) = session.stateBag
        .tryGetValue<List<ToolApprovalRequestContent>>(stateBagKey);
    if (!found || pendingRequests == null || pendingRequests.isEmpty) {
      return messages;
    }

    session.stateBag.tryRemoveValue(stateBagKey);

    final approvalResponses = <AIContent>[
      for (final request in pendingRequests) request.createResponse(true),
    ];

    return [
      ...messages,
      ChatMessage(role: ChatRole.user, contents: approvalResponses),
    ];
  }

  /// Builds a set of tool names that do not require approval and can be
  /// auto-approved, by checking all available tools from [ChatOptions.tools]
  /// and [FunctionInvokingChatClient.additionalTools].
  Set<String> _getAutoApprovableToolNames(ChatOptions? options) {
    final functionInvoking = getService<FunctionInvokingChatClient>();

    final allTools = <AITool>[
      ...?options?.tools,
      ...?functionInvoking?.additionalTools,
    ];

    return {
      for (final tool in allTools.whereType<AIFunction>())
        if (!_requiresApproval(tool)) tool.name,
    };
  }

  /// Returns `true` when [function] is (or wraps) an
  /// [ApprovalRequiredAIFunction].
  static bool _requiresApproval(AIFunction function) {
    AIFunction current = function;
    while (true) {
      if (current is ApprovalRequiredAIFunction) {
        return true;
      }
      if (current is DelegatingAIFunction) {
        current = current.innerFunction;
        continue;
      }
      return false;
    }
  }

  /// Determines whether a [ToolApprovalRequestContent] can be auto-approved
  /// because the underlying tool is not an [ApprovalRequiredAIFunction].
  ///
  /// Unknown tools are not in the set and are treated as approval-required
  /// (safe default). Non-function tool calls cannot be auto-approved.
  static bool _isAutoApprovable(
    ToolApprovalRequestContent approval,
    Set<String> autoApprovableNames,
  ) {
    final dynamic toolCall = approval.toolCall;
    if (toolCall is! FunctionCallContent) {
      return false;
    }
    return autoApprovableNames.contains(toolCall.name);
  }

  /// Scans response messages for auto-approvable
  /// [ToolApprovalRequestContent] items, removes them from the messages, and
  /// stores them in the session for the next request.
  static void _removeAutoApprovedFromMessages(
    List<ChatMessage> messages,
    Set<String> autoApprovableNames,
    AgentSession session,
  ) {
    final autoApproved = <ToolApprovalRequestContent>[];

    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final remaining = <AIContent>[];
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent &&
            _isAutoApprovable(content, autoApprovableNames)) {
          autoApproved.add(content);
        } else {
          remaining.add(content);
        }
      }
      if (remaining.length == message.contents.length) {
        continue;
      }
      if (remaining.isEmpty) {
        messages.removeAt(i);
      } else {
        message.contents
          ..clear()
          ..addAll(remaining);
      }
    }

    if (autoApproved.isNotEmpty) {
      session.stateBag.setValue<List<ToolApprovalRequestContent>>(
        stateBagKey,
        autoApproved,
      );
    }
  }

  /// Filters auto-approvable [ToolApprovalRequestContent] items from a
  /// streaming update's contents, collecting them into [autoApproved].
  ///
  /// Returns `true` if the update should be yielded (has remaining content or
  /// had no approval content to begin with); `false` if the update is now
  /// empty and should be skipped.
  static bool _filterUpdateContents(
    ChatResponseUpdate update,
    Set<String> autoApprovableNames,
    List<ToolApprovalRequestContent> autoApproved,
  ) {
    var hasApprovalContent = false;
    final filteredContents = <AIContent>[];
    var removedAny = false;

    for (final content in update.contents) {
      if (content is ToolApprovalRequestContent) {
        hasApprovalContent = true;
        if (_isAutoApprovable(content, autoApprovableNames)) {
          autoApproved.add(content);
          removedAny = true;
        } else {
          filteredContents.add(content);
        }
      } else {
        filteredContents.add(content);
      }
    }

    if (removedAny) {
      update.contents
        ..clear()
        ..addAll(filteredContents);
    }

    return update.contents.isNotEmpty || !hasApprovalContent;
  }
}
