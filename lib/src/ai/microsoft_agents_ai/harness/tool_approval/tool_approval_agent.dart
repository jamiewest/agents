import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/delegating_ai_agent.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../../../json_stubs.dart';
import '../../agent_json_utilities.dart';
import 'always_approve_tool_approval_response_content.dart';
import 'tool_approval_rule.dart';
import 'tool_approval_state.dart';

/// Middleware that handles standing tool-approval rules and queues approval
/// requests so callers see at most one unresolved request at a time.
class ToolApprovalAgent extends DelegatingAIAgent {
  ToolApprovalAgent(
    AIAgent? innerAgent, {
    JsonSerializerOptions? jsonSerializerOptions,
  }) : _jsonSerializerOptions =
           jsonSerializerOptions ?? AgentJsonUtilities.defaultOptions,
       _sessionState = ProviderSessionState<ToolApprovalState>(
         (_) => ToolApprovalState(),
         'toolApprovalState',
         JsonSerializerOptions:
             jsonSerializerOptions ?? AgentJsonUtilities.defaultOptions,
       ),
       super(innerAgent ?? (throw ArgumentError.notNull('innerAgent')));

  final ProviderSessionState<ToolApprovalState> _sessionState;
  final JsonSerializerOptions _jsonSerializerOptions;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final inbound = prepareInboundMessages(messages, session);
    var state = inbound.state;
    var callerMessages = inbound.callerMessages;

    if (inbound.nextQueuedItem != null) {
      return AgentResponse(
        message: ChatMessage(
          role: ChatRole.assistant,
          contents: [inbound.nextQueuedItem!],
        ),
      );
    }

    while (true) {
      final processedMessages = injectCollectedResponses(
        callerMessages,
        state,
        session,
      );
      final response = await innerAgent.run(
        session,
        options,
        cancellationToken: cancellationToken,
        messages: processedMessages,
      );
      final allAutoApproved = processAndQueueOutboundApprovalRequests(
        response.messages,
        state,
        session,
      );
      if (!allAutoApproved) {
        return response;
      }

      callerMessages = const [];
    }
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final inbound = prepareInboundMessages(messages, session);
    var state = inbound.state;
    var callerMessages = inbound.callerMessages;

    if (inbound.nextQueuedItem != null) {
      yield AgentResponseUpdate(
        role: ChatRole.assistant,
        contents: [inbound.nextQueuedItem!],
      );
      return;
    }

    while (true) {
      final processedMessages = injectCollectedResponses(
        callerMessages,
        state,
        session,
      );
      final streamedApprovalRequests = <ToolApprovalRequestContent>[];

      await for (final update in innerAgent.runStreaming(
        session,
        options,
        cancellationToken: cancellationToken,
        messages: processedMessages,
      )) {
        final approvalRequests = update.contents
            .whereType<ToolApprovalRequestContent>()
            .toList();
        if (approvalRequests.isEmpty) {
          yield update;
          continue;
        }

        streamedApprovalRequests.addAll(approvalRequests);
        final filteredContents = update.contents
            .where((content) => content is! ToolApprovalRequestContent)
            .toList();
        if (filteredContents.isNotEmpty) {
          yield _cloneUpdateWithContents(update, filteredContents);
        }
      }

      if (streamedApprovalRequests.isEmpty) {
        return;
      }

      final unapproved = <ToolApprovalRequestContent>[];
      for (final request in streamedApprovalRequests) {
        if (matchesRule(request, state.rules, _jsonSerializerOptions)) {
          state.collectedApprovalResponses.add(
            request.createResponse(
              true,
              reason: 'Auto-approved by standing rule',
            ),
          );
        } else {
          unapproved.add(request);
        }
      }

      if (unapproved.isEmpty) {
        _sessionState.saveState(session, state);
        callerMessages = const [];
        continue;
      }

      if (unapproved.length > 1) {
        state.queuedApprovalRequests.addAll(unapproved.skip(1));
      }
      _sessionState.saveState(session, state);
      yield AgentResponseUpdate(
        role: ChatRole.assistant,
        contents: [unapproved.first],
      );
      return;
    }
  }

  ({
    ToolApprovalState state,
    List<ChatMessage> callerMessages,
    ToolApprovalRequestContent? nextQueuedItem,
  })
  prepareInboundMessages(
    Iterable<ChatMessage> messages,
    AgentSession? session,
  ) {
    final state = _sessionState.getOrInitializeState(session);
    final callerMessages = unwrapAlwaysApproveResponses(
      messages,
      state,
      _jsonSerializerOptions,
    );

    collectApprovalResponsesFromMessages(callerMessages, state);

    if (state.queuedApprovalRequests.isNotEmpty) {
      drainAutoApprovableFromQueue(state);
      if (state.queuedApprovalRequests.isNotEmpty) {
        final next = state.queuedApprovalRequests.removeAt(0);
        _sessionState.saveState(session, state);
        return (
          state: state,
          callerMessages: callerMessages,
          nextQueuedItem: next,
        );
      }
    }

    return (state: state, callerMessages: callerMessages, nextQueuedItem: null);
  }

  static void collectApprovalResponsesFromMessages(
    List<ChatMessage> messages,
    ToolApprovalState state,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (!message.contents.any((c) => c is ToolApprovalResponseContent)) {
        continue;
      }

      final remaining = <AIContent>[];
      for (final content in message.contents) {
        if (content is ToolApprovalResponseContent) {
          state.collectedApprovalResponses.add(content);
        } else {
          remaining.add(content);
        }
      }

      if (remaining.isEmpty) {
        messages.removeAt(i);
      } else {
        messages[i] = _cloneMessageWithContents(message, remaining);
      }
    }
  }

  void drainAutoApprovableFromQueue(ToolApprovalState state) {
    for (var i = state.queuedApprovalRequests.length - 1; i >= 0; i--) {
      final request = state.queuedApprovalRequests[i];
      if (matchesRule(request, state.rules, _jsonSerializerOptions)) {
        state.collectedApprovalResponses.add(
          request.createResponse(
            true,
            reason: 'Auto-approved by standing rule',
          ),
        );
        state.queuedApprovalRequests.removeAt(i);
      }
    }
  }

  List<ChatMessage> injectCollectedResponses(
    List<ChatMessage> callerMessages,
    ToolApprovalState state,
    AgentSession? session,
  ) {
    if (state.collectedApprovalResponses.isEmpty) {
      return callerMessages;
    }

    final result = <ChatMessage>[
      ChatMessage(
        role: ChatRole.user,
        contents: List<AIContent>.of(state.collectedApprovalResponses),
      ),
      ...callerMessages,
    ];
    state.collectedApprovalResponses.clear();
    _sessionState.saveState(session, state);
    return result;
  }

  bool processAndQueueOutboundApprovalRequests(
    List<ChatMessage> responseMessages,
    ToolApprovalState state,
    AgentSession? session,
  ) {
    final autoApproved = <ToolApprovalRequestContent>[];
    final unapproved = <ToolApprovalRequestContent>[];

    for (final message in responseMessages) {
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          if (matchesRule(content, state.rules, _jsonSerializerOptions)) {
            autoApproved.add(content);
          } else {
            unapproved.add(content);
          }
        }
      }
    }

    if (autoApproved.isEmpty && unapproved.length <= 1) {
      return false;
    }

    for (final request in autoApproved) {
      state.collectedApprovalResponses.add(
        request.createResponse(true, reason: 'Auto-approved by standing rule'),
      );
    }

    if (unapproved.isEmpty) {
      removeAllToolApprovalRequests(responseMessages);
      _sessionState.saveState(session, state);
      return true;
    }

    final toRemove = <ToolApprovalRequestContent>{...autoApproved};
    if (unapproved.length > 1) {
      for (final request in unapproved.skip(1)) {
        toRemove.add(request);
        state.queuedApprovalRequests.add(request);
      }
    }

    removeToolApprovalRequests(responseMessages, toRemove);
    _sessionState.saveState(session, state);
    return false;
  }

  static void removeAllToolApprovalRequests(
    List<ChatMessage> responseMessages,
  ) {
    removeToolApprovalRequests(
      responseMessages,
      responseMessages
          .expand((message) => message.contents)
          .whereType<ToolApprovalRequestContent>()
          .toSet(),
    );
  }

  static void removeToolApprovalRequests(
    List<ChatMessage> responseMessages,
    Set<ToolApprovalRequestContent> requests,
  ) {
    if (requests.isEmpty) {
      return;
    }

    for (var i = responseMessages.length - 1; i >= 0; i--) {
      final message = responseMessages[i];
      if (!message.contents.any(
        (content) =>
            content is ToolApprovalRequestContent && requests.contains(content),
      )) {
        continue;
      }

      final remaining = message.contents
          .where(
            (content) =>
                content is! ToolApprovalRequestContent ||
                !requests.contains(content),
          )
          .toList();
      if (remaining.isEmpty) {
        responseMessages.removeAt(i);
      } else {
        responseMessages[i] = _cloneMessageWithContents(message, remaining);
      }
    }
  }

  static List<ChatMessage> unwrapAlwaysApproveResponses(
    Iterable<ChatMessage> messages,
    ToolApprovalState state,
    JsonSerializerOptions jsonSerializerOptions,
  ) {
    final messageList = List<ChatMessage>.of(messages);
    var anyModified = false;
    final result = <ChatMessage>[];

    for (final message in messageList) {
      if (!message.contents.any(
        (c) => c is AlwaysApproveToolApprovalResponseContent,
      )) {
        result.add(message);
        continue;
      }

      final newContents = <AIContent>[];
      for (final content in message.contents) {
        if (content is AlwaysApproveToolApprovalResponseContent) {
          final toolCall = _asFunctionCall(content.innerResponse.toolCall);
          if (toolCall != null) {
            if (content.alwaysApproveTool) {
              addRuleIfNotExists(
                state,
                ToolApprovalRule(toolName: toolCall.name),
              );
            } else if (content.alwaysApproveToolWithArguments) {
              addRuleIfNotExists(
                state,
                ToolApprovalRule(
                  toolName: toolCall.name,
                  arguments: serializeArguments(
                    toolCall.arguments,
                    jsonSerializerOptions,
                  ),
                ),
              );
            }
          }
          newContents.add(content.innerResponse);
        } else {
          newContents.add(content);
        }
      }

      result.add(_cloneMessageWithContents(message, newContents));
      anyModified = true;
    }

    return anyModified ? result : messageList;
  }

  static bool matchesRule(
    ToolApprovalRequestContent request,
    List<ToolApprovalRule> rules,
    JsonSerializerOptions jsonSerializerOptions,
  ) {
    final toolCall = _asFunctionCall(request.toolCall);
    if (toolCall == null) {
      return false;
    }

    for (final rule in rules) {
      if (rule.toolName != toolCall.name) {
        continue;
      }
      if (rule.arguments == null) {
        return true;
      }
      if (argumentsMatch(
        rule.arguments!,
        toolCall.arguments,
        jsonSerializerOptions,
      )) {
        return true;
      }
    }

    return false;
  }

  static bool argumentsMatch(
    Map<String, String> ruleArguments,
    Map<String, Object?>? callArguments,
    JsonSerializerOptions jsonSerializerOptions,
  ) {
    if (callArguments == null) {
      return ruleArguments.isEmpty;
    }
    if (ruleArguments.length != callArguments.length) {
      return false;
    }

    for (final entry in ruleArguments.entries) {
      if (!callArguments.containsKey(entry.key)) {
        return false;
      }
      final serializedCallValue = serializeArgumentValue(
        callArguments[entry.key],
        jsonSerializerOptions,
      );
      if (entry.value != serializedCallValue) {
        return false;
      }
    }

    return true;
  }

  static Map<String, String>? serializeArguments(
    Map<String, Object?>? arguments,
    JsonSerializerOptions jsonSerializerOptions,
  ) {
    if (arguments == null || arguments.isEmpty) {
      return null;
    }

    return {
      for (final entry in arguments.entries)
        entry.key: serializeArgumentValue(entry.value, jsonSerializerOptions),
    };
  }

  static String serializeArgumentValue(
    Object? value,
    JsonSerializerOptions jsonSerializerOptions,
  ) {
    if (value == null) {
      return 'null';
    }
    if (value is JsonElement) {
      return value.toString();
    }
    return JsonSerializer.serialize(value);
  }

  static void addRuleIfNotExists(
    ToolApprovalState state,
    ToolApprovalRule newRule,
  ) {
    for (final existingRule in state.rules) {
      if (existingRule.toolName != newRule.toolName) {
        continue;
      }
      if (existingRule.arguments == null && newRule.arguments == null) {
        return;
      }
      if (existingRule.arguments != null &&
          newRule.arguments != null &&
          argumentDictionariesEqual(
            existingRule.arguments!,
            newRule.arguments!,
          )) {
        return;
      }
    }

    state.rules.add(newRule);
  }

  static bool argumentDictionariesEqual(
    Map<String, String> a,
    Map<String, String> b,
  ) {
    if (a.length != b.length) {
      return false;
    }

    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  static FunctionCallContent? _asFunctionCall(ToolCallContent toolCall) {
    final dynamic candidate = toolCall;
    return candidate is FunctionCallContent ? candidate : null;
  }

  static ChatMessage _cloneMessageWithContents(
    ChatMessage message,
    List<AIContent> contents,
  ) {
    return ChatMessage(
      role: message.role,
      contents: contents,
      authorName: message.authorName,
      createdAt: message.createdAt,
      messageId: message.messageId,
      rawRepresentation: message.rawRepresentation,
      additionalProperties: message.additionalProperties != null
          ? Map.of(message.additionalProperties!)
          : null,
    );
  }

  static AgentResponseUpdate _cloneUpdateWithContents(
    AgentResponseUpdate update,
    List<AIContent> contents,
  ) {
    final clone = AgentResponseUpdate(role: update.role, contents: contents);
    clone.authorName = update.authorName;
    clone.rawRepresentation = update.rawRepresentation;
    clone.additionalProperties = update.additionalProperties != null
        ? Map.of(update.additionalProperties!)
        : null;
    clone.agentId = update.agentId;
    clone.responseId = update.responseId;
    clone.messageId = update.messageId;
    clone.createdAt = update.createdAt;
    clone.continuationToken = update.continuationToken;
    clone.finishReason = update.finishReason;
    return clone;
  }
}
