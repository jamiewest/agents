import 'dart:async';

import 'package:extensions/ai.dart';
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
/// This decorator requires an active [AIAgent.currentRunContext] with a
/// non-null session; a [StateError] is thrown otherwise.
class NonApprovalRequiredFunctionBypassingChatClient
    extends DelegatingChatClient {
  /// Creates the decorator wrapping [innerClient] (typically a
  /// [FunctionInvokingChatClient]).
  NonApprovalRequiredFunctionBypassingChatClient(super.innerClient);

  /// The key used in the session state bag to store pending auto-approved
  /// function calls between agent runs.
  static const String stateBagKey = '_autoApprovedFunctionCalls';

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final session = _getRequiredSession();
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
    final session = _getRequiredSession();
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

  /// Gets the current [AgentSession] from the ambient run context.
  static AgentSession _getRequiredSession() {
    final runContext = AIAgent.currentRunContext;
    if (runContext == null) {
      throw StateError(
        'NonApprovalRequiredFunctionBypassingChatClient can only be used '
        'within the context of a running AIAgent. Ensure that the chat '
        'client is being invoked as part of an AIAgent.run or '
        'AIAgent.runStreaming call.',
      );
    }
    final session = runContext.session;
    if (session == null) {
      throw StateError(
        'NonApprovalRequiredFunctionBypassingChatClient requires a session. '
        'Ensure the agent has a resolved session before invoking the chat '
        'client.',
      );
    }
    return session;
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
