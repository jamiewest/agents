import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/delegating_ai_agent.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import 'always_approve_tool_approval_response_content.dart';
import 'tool_approval_rule.dart';
import 'tool_approval_state.dart';
import '../../../../json_stubs.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

/// A [DelegatingAIAgent] middleware that implements "don't ask again" tool
/// approval behavior and queues multiple approval requests to present them to
/// the caller one at a time.
///
/// Remarks: This middleware intercepts the approval flow between the caller
/// and the inner agent: Outbound (response to caller): When the inner agent
/// surfaces [ToolApprovalRequestContent] items, the middleware checks whether
/// matching [ToolApprovalRule] entries have been recorded. Matched requests
/// are auto-approved and stored as collected approval responses. If multiple
/// unapproved requests remain, only the first is returned to the caller while
/// the rest are queued. On subsequent calls, queued items are re-evaluated
/// against rules (which may have been updated by the caller's "always
/// approve" response) and presented one at a time. Once all queued requests
/// are resolved, the collected responses are injected and the inner agent is
/// called again. Inbound (caller to agent): When the caller sends an
/// [AlwaysApproveToolApprovalResponseContent], the middleware extracts the
/// standing approval settings, records them as [ToolApprovalRule] entries in
/// the session state, and forwards only the unwrapped
/// [ToolApprovalResponseContent] to the inner agent. Content ordering within
/// each message is preserved. Approval rules are persisted in the
/// [AgentSessionStateBag] and survive across agent runs within the same
/// session. Two categories of rules are supported: Tool-level: Approve all
/// calls to a specific tool, regardless of arguments. Tool+arguments: Approve
/// all calls to a specific tool with exactly matching arguments.
class ToolApprovalAgent extends DelegatingAIAgent {
  /// Initializes a new instance of the [ToolApprovalAgent] class.
  ///
  /// [innerAgent] The underlying agent to delegate to.
  ///
  /// [JsonSerializerOptions] Optional [JsonSerializerOptions] used for
  /// serializing argument values when storing rules and for persisting state.
  /// When `null`, [DefaultOptions] is used.
  ToolApprovalAgent(AIAgent innerAgent, {JsonSerializerOptions? JsonSerializerOptions = null, }) : super(innerAgent) {
    this._jsonSerializerOptions = JsonSerializerOptions ?? AgentJsonUtilities.defaultOptions;
    this._sessionState = ProviderSessionState<ToolApprovalState>(
            (_) => toolApprovalState(),
            "toolApprovalState",
            this._jsonSerializerOptions);
  }

  late final ProviderSessionState<ToolApprovalState> _sessionState;

  late final JsonSerializerOptions _jsonSerializerOptions;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, }
  ) async {
    // Steps 1–2: Unwrap AlwaysApprove wrappers, process any queued approval requests.
        var (
          state,
          callerMessages,
          nextQueuedItem,
        ) = this.prepareInboundMessages(messages, session);
    if (nextQueuedItem != null) {
      return agentResponse(ChatMessage(role: ChatRole.assistant, contents: [nextQueuedItem]));
    }
    while (true) {
      var processedMessages = this.injectCollectedResponses(callerMessages, state, session);
      var response = await this.innerAgent.runAsync(
        processedMessages,
        session,
        options,
        cancellationToken,
      ) ;
      var allAutoApproved = this.processAndQueueOutboundApprovalRequests(
        response.messages,
        state,
        session,
      );
      if (!allAutoApproved) {
        return response;
      }
      // All approval requests were auto-approved. Loop to re-invoke with them injected.
            callerMessages = [];
    }
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, }
  ) async* {
    // Steps 1–2: Unwrap AlwaysApprove wrappers, process any queued approval requests.
        var (
          state,
          callerMessages,
          nextQueuedItem,
        ) = this.prepareInboundMessages(messages, session);
    if (nextQueuedItem != null) {
      yield AgentResponseUpdate(role: ChatRole.assistant, contents: [nextQueuedItem]);
      return;
    }
    while (true) {
      var processedMessages = this.injectCollectedResponses(callerMessages, state, session);
      var streamedApprovalRequests = [];
      for (final update in this.innerAgent.runStreamingAsync(processedMessages, session, options, cancellationToken)) {
        var hasApprovalRequests = false;
        for (final content in update.contents) {
          if (content is ToolApprovalRequestContent) {
            hasApprovalRequests = true;
            break;
          }
        }
        if (!hasApprovalRequests) {
          yield update;
          continue;
        }
        var filteredContents = List<AIContent>();
        for (final content in update.contents) {
          if (content is ToolApprovalRequestContent) {
            final tarc = content as ToolApprovalRequestContent;
            streamedApprovalRequests.add(tarc);
          } else {
            filteredContents.add(content);
          }
        }
        if (filteredContents.length > 0) {
          yield AgentResponseUpdate(role: update.role, contents: filteredContents);
        }
      }
      if (streamedApprovalRequests.length == 0) {
        return;
      }
      var unapproved = [];
      for (final tarc in streamedApprovalRequests) {
        if (matchesRule(tarc, state.rules, this._jsonSerializerOptions)) {
          state.collectedApprovalResponses.add(
                        tarc.createResponse(
                          approved: true,
                          reason: "Auto-approved by standing rule",
                        ) );
        } else {
          unapproved.add(tarc);
        }
      }
      if (unapproved.length == 0) {
        callerMessages = [];
        continue;
      }
      if (unapproved.length > 1) {
        state.queuedApprovalRequests.addAll(unapproved.getRange(1, unapproved.length - 1));
      }
      this._sessionState.saveState(session, state);
      yield AgentResponseUpdate(role: ChatRole.assistant, contents: [unapproved[0]]);
      return;
    }
  }

  /// Extracts [ToolApprovalResponseContent] instances from the caller's
  /// messages and collects them into [CollectedApprovalResponses]. Extracted
  /// responses are removed from the messages in-place.
  static void collectApprovalResponsesFromMessages(
    List<ChatMessage> messages,
    ToolApprovalState state,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      var message = messages[i];
      var hasApprovalResponse = false;
      for (final content in message.contents) {
        if (content is ToolApprovalResponseContent) {
          hasApprovalResponse = true;
          break;
        }
      }
      if (!hasApprovalResponse) {
        continue;
      }
      var remaining = List<AIContent>(message.contents.length);
      for (final content in message.contents) {
        if (content is ToolApprovalResponseContent) {
          final response = content as ToolApprovalResponseContent;
          state.collectedApprovalResponses.add(response);
        } else {
          remaining.add(content);
        }
      }
      if (remaining.length == 0) {
        messages.removeAt(i);
      } else {
        var cloned = message.clone();
        cloned.contents = remaining;
        messages[i] = cloned;
      }
    }
  }

  /// Re-evaluates queued approval requests against current rules and
  /// auto-approves any that now match.
  void drainAutoApprovableFromQueue(ToolApprovalState state) {
    for (var i = state.queuedApprovalRequests.length - 1; i >= 0; i--) {
      if (matchesRule(state.queuedApprovalRequests[i], state.rules, this._jsonSerializerOptions)) {
        state.collectedApprovalResponses.add(
                    state.queuedApprovalRequests[i].createResponse(
                      approved: true,
                      reason: "Auto-approved by standing rule",
                    ) );
        state.queuedApprovalRequests.removeAt(i);
      }
    }
  }

  /// Performs the common inbound processing shared by both the streaming and
  /// non-streaming paths: Unwraps [AlwaysApproveToolApprovalResponseContent]
  /// wrappers, extracting standing rules. If there are queued approval requests
  /// from a previous batch, collects the caller's responses, drains any items
  /// now resolvable by new rules, and dequeues the next item if any remain.
  ///
  /// Returns: A tuple of (state, processed caller messages, next queued item or
  /// `null` if the queue is resolved). When the returned item is non-null, the
  /// caller should return/yield it without calling the inner agent.
  Object? prepareInboundMessages(
    Iterable<ChatMessage> messages,
    AgentSession? session,
  ) {
    var state = this._sessionState.getOrInitializeState(session);
    var callerMessages = unwrapAlwaysApproveResponses(messages, state, this._jsonSerializerOptions);
    if (state.queuedApprovalRequests.length > 0) {
      // Collect the caller's approval/denial responses for the previously dequeued item
            // and store them in state for the next downstream call.
            collectApprovalResponsesFromMessages(callerMessages, state);
      // Re-evaluate remaining queued items — the caller may have added new rules
            // (e.g., "always approve this tool") that resolve additional items.
            this.drainAutoApprovableFromQueue(state);
      if (state.queuedApprovalRequests.length > 0) {
        var next = state.queuedApprovalRequests[0];
        state.queuedApprovalRequests.removeAt(0);
        this._sessionState.saveState(session, state);
        return (state, callerMessages, next);
      }
    }
    return (state, callerMessages, null);
  }

  /// Injects any collected approval responses as user messages before the
  /// caller's messages, then clears the collected responses.
  List<ChatMessage> injectCollectedResponses(
    List<ChatMessage> callerMessages,
    ToolApprovalState state,
    AgentSession? session,
  ) {
    if (state.collectedApprovalResponses.length > 0) {
      var result = [ChatMessage(role: ChatRole.user, contents: [...state.collectedApprovalResponses])];
      result.addAll(callerMessages);
      state.collectedApprovalResponses.clear();
      this._sessionState.saveState(session, state);
      return result;
    }
    return callerMessages;
  }

  /// Processes outbound approval requests from non-streaming response messages.
  /// Auto-approvable requests are collected as responses, and if multiple
  /// unapproved requests remain, only the first is kept in the response while
  /// the rest are queued for subsequent calls.
  ///
  /// Returns: `true` if all TARc items were auto-approved (caller should
  /// re-invoke the inner agent); `false` otherwise.
  bool processAndQueueOutboundApprovalRequests(
    List<ChatMessage> responseMessages,
    ToolApprovalState state,
    AgentSession? session,
  ) {
    var autoApproved = List<ToolApprovalRequestContent>();
    var unapproved = List<ToolApprovalRequestContent>();
    for (final message in responseMessages) {
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          final tarc = content as ToolApprovalRequestContent;
          if (matchesRule(tarc, state.rules, this._jsonSerializerOptions)) {
            autoApproved.add(tarc);
          } else {
            unapproved.add(tarc);
          }
        }
      }
    }
    if (autoApproved.length == 0 && unapproved.length <= 1) {
      return false;
    }
    for (final tarc in autoApproved) {
      state.collectedApprovalResponses.add(
                tarc.createResponse(approved: true, reason: "Auto-approved by standing rule"));
    }
    if (unapproved.length == 0) {
      removeAllToolApprovalRequests(responseMessages);
      this._sessionState.saveState(session, state);
      return true;
    }
    var toRemove = Set<ToolApprovalRequestContent>(autoApproved);
    if (unapproved.length > 1) {
      for (var i = 1; i < unapproved.length; i++) {
        toRemove.add(unapproved[i]);
        state.queuedApprovalRequests.add(unapproved[i]);
      }
    }
    for (var i = responseMessages.length - 1; i >= 0; i--) {
      var message = responseMessages[i];
      var hasRemovable = false;
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent && toRemove.contains(tarc)) {
          hasRemovable = true;
          break;
        }
      }
      if (!hasRemovable) {
        continue;
      }
      var remaining = List<AIContent>(message.contents.length);
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent && toRemove.contains(tarc)) {
          continue;
        }
        remaining.add(content);
      }
      if (remaining.length == 0) {
        responseMessages.removeAt(i);
      } else {
        var clonedMessage = message.clone();
        clonedMessage.contents = remaining;
        responseMessages[i] = clonedMessage;
      }
    }
    this._sessionState.saveState(session, state);
    return false;
  }

  /// Removes all [ToolApprovalRequestContent] items from response messages.
  static void removeAllToolApprovalRequests(List<ChatMessage> responseMessages) {
    for (var i = responseMessages.length - 1; i >= 0; i--) {
      var message = responseMessages[i];
      var hasTarc = false;
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          hasTarc = true;
          break;
        }
      }
      if (!hasTarc) {
        continue;
      }
      var remaining = List<AIContent>(message.contents.length);
      for (final content in message.contents) {
        if (content is! ToolApprovalRequestContent) {
          remaining.add(content);
        }
      }
      if (remaining.length == 0) {
        responseMessages.removeAt(i);
      } else {
        var clonedMessage = message.clone();
        clonedMessage.contents = remaining;
        responseMessages[i] = clonedMessage;
      }
    }
  }

  /// Scans input messages for [AlwaysApproveToolApprovalResponseContent]
  /// instances, extracts standing approval rules, and replaces them in-place
  /// with the unwrapped inner [ToolApprovalResponseContent], preserving content
  /// ordering.
  static List<ChatMessage> unwrapAlwaysApproveResponses(
    Iterable<ChatMessage> messages,
    ToolApprovalState state,
    JsonSerializerOptions JsonSerializerOptions,
  ) {
    var messageList = messages is List<ChatMessage> ? messages as List<ChatMessage> : messages.toList();
    var result = List<ChatMessage>(messageList.length);
    var anyModified = false;
    for (final message in messageList) {
      var hasAlwaysApprove = false;
      for (final content in message.contents) {
        if (content is AlwaysApproveToolApprovalResponseContent) {
          hasAlwaysApprove = true;
          break;
        }
      }
      if (!hasAlwaysApprove) {
        result.add(message);
        continue;
      }
      var newContents = List<AIContent>(message.contents.length);
      for (final content in message.contents) {
        if (content is AlwaysApproveToolApprovalResponseContent) {
          final alwaysApprove = content as AlwaysApproveToolApprovalResponseContent;
          if (alwaysApprove.innerResponse.toolCall is FunctionCallContent) {
            final toolCall = alwaysApprove.innerResponse.toolCall as FunctionCallContent;
            if (alwaysApprove.alwaysApproveTool) {
              addRuleIfNotExists(state, toolApprovalRule());
            } else if (alwaysApprove.alwaysApproveToolWithArguments) {
              addRuleIfNotExists(state, toolApprovalRule());
            }
          }
          // Replace the wrapper with the unwrapped inner response, preserving position.
                    newContents.add(alwaysApprove.innerResponse);
        } else {
          newContents.add(content);
        }
      }
      var clonedMessage = message.clone();
      clonedMessage.contents = newContents;
      result.add(clonedMessage);
      anyModified = true;
    }
    return anyModified ? result : (messageList is List<ChatMessage> ? messageList as List<ChatMessage> : messageList.toList());
  }

  /// Determines whether a tool approval request matches any of the stored
  /// rules.
  static bool matchesRule(
    ToolApprovalRequestContent request,
    List<ToolApprovalRule> rules,
    JsonSerializerOptions JsonSerializerOptions,
  ) {
    if (request.toolCall is! FunctionCallContent) {
      return false;
    }
    for (final rule in rules) {
      if (!(rule.toolName == functionCall.name)) {
        continue;
      }
      if (rule.arguments == null) {
        return true;
      }
      if (argumentsMatch(rule.arguments, functionCall.arguments, JsonSerializerOptions)) {
        return true;
      }
    }
    return false;
  }

  /// Compares stored rule arguments against actual function call arguments for
  /// an exact match.
  static bool argumentsMatch(
    Map<String, String> ruleArguments,
    Map<String, Object?>? callArguments,
    JsonSerializerOptions JsonSerializerOptions,
  ) {
    if (callArguments == null) {
      return ruleArguments.length == 0;
    }
    if (ruleArguments.length != callArguments.length) {
      return false;
    }
    for (final kvp in ruleArguments) {
      var callValue;
      if (!callArguments.containsKey(kvp.key)) {
        return false;
      }
      var serializedCallValue = serializeArgumentValue(callValue, JsonSerializerOptions);
      if (!(kvp.value == serializedCallValue)) {
        return false;
      }
    }
    return true;
  }

  /// Serializes function call arguments to a String dictionary for storage and
  /// comparison.
  static Map<String, String>? serializeArguments(
    Map<String, Object?>? arguments,
    JsonSerializerOptions JsonSerializerOptions,
  ) {
    if (arguments == null || arguments.length == 0) {
      return null;
    }
    var serialized = new Dictionary<String, String>(arguments.length, );
    for (final kvp in arguments) {
      serialized[kvp.key] = serializeArgumentValue(kvp.value, JsonSerializerOptions);
    }
    return serialized;
  }

  /// Serializes a single argument value to its JSON String representation.
  static String serializeArgumentValue(
    Object? value,
    JsonSerializerOptions JsonSerializerOptions,
  ) {
    if (value == null) {
      return "null";
    }
    if (value is JsonElement) {
      final jsonElement = value as JsonElement;
      return jsonElement.getRawText();
    }
    return JsonSerializer.serialize(value, JsonSerializerOptions.getTypeInfo(value.runtimeType));
  }

  /// Adds a rule to the state if an equivalent rule does not already exist.
  static void addRuleIfNotExists(ToolApprovalState state, ToolApprovalRule newRule, ) {
    for (final existingRule in state.rules) {
      if (!(existingRule.toolName == newRule.toolName)) {
        continue;
      }
      if (existingRule.arguments == null&& newRule.arguments == null) {
        return;
      }
      if (existingRule.arguments != null&& newRule.arguments != null &&
                argumentDictionariesEqual(existingRule.arguments, newRule.arguments)) {
        return;
      }
    }
    state.rules.add(newRule);
  }

  /// Compares two String dictionaries for equality.
  static bool argumentDictionariesEqual(Map<String, String> a, Map<String, String> b, ) {
    if (a.length != b.length) {
      return false;
    }
    for (final kvp in a) {
      var bValue;
      if (!b.containsKey(kvp.key) || !(kvp.value == bValue)) {
        return false;
      }
    }
    return true;
  }
}
