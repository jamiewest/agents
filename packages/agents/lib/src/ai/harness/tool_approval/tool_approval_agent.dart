import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_response.dart';
import '../../../abstractions/agent_response_update.dart';
import '../../../abstractions/agent_run_options.dart';
import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../../abstractions/delegating_ai_agent.dart';
import '../../../abstractions/provider_session_state.dart';
import '../../../json_stubs.dart';
import '../../../shared/usage_aggregation_extensions.dart';
import '../../../shared/usage_aggregator.dart';
import '../../agent_json_utilities.dart';
import 'always_approve_tool_approval_response_content.dart';
import 'tool_approval_agent_options.dart';
import 'tool_approval_rule.dart';
import 'tool_approval_state.dart';
import 'tool_auto_approval_rule_context.dart';

/// Middleware that handles standing tool-approval rules and queues approval
/// requests so callers see at most one unresolved request at a time.
class ToolApprovalAgent extends DelegatingAIAgent {
  ToolApprovalAgent(AIAgent? innerAgent, {ToolApprovalAgentOptions? options})
    : _jsonSerializerOptions =
          options?.jsonSerializerOptions ?? AgentJsonUtilities.defaultOptions,
      _autoApprovalRules = options?.autoApprovalRules?.toList(),
      _maxAutoApprovalIterations = _checkIterations(
        options?.maxAutoApprovalIterations ?? defaultMaxAutoApprovalIterations,
      ),
      _sessionState = ProviderSessionState<ToolApprovalState>(
        (_) => ToolApprovalState(),
        'toolApprovalState',
        stateRehydrator: ToolApprovalState.fromJson,
        jsonSerializerOptions:
            options?.jsonSerializerOptions ?? AgentJsonUtilities.defaultOptions,
      ),
      super(innerAgent ?? (throw ArgumentError.notNull('innerAgent')));

  /// The default value used for
  /// [ToolApprovalAgentOptions.maxAutoApprovalIterations] when none is
  /// specified.
  static const int defaultMaxAutoApprovalIterations = 40;

  final ProviderSessionState<ToolApprovalState> _sessionState;
  final JsonSerializerOptions _jsonSerializerOptions;
  final List<ToolAutoApprovalRule>? _autoApprovalRules;
  final int _maxAutoApprovalIterations;

  static int _checkIterations(int value) => value < 1
      ? throw ArgumentError.value(
          value,
          'maxAutoApprovalIterations',
          'must be at least 1',
        )
      : value;

  /// An auto-approval rule that approves every function call.
  ///
  /// Add this rule to [ToolApprovalAgentOptions.autoApprovalRules] to
  /// automatically approve all tool calls without prompting the user.
  static ToolAutoApprovalRule get allToolsAutoApprovalRule =>
      _allToolsAutoApprovalRule;

  static Future<bool> _allToolsAutoApprovalRule(
    ToolAutoApprovalRuleContext context,
  ) async => true;

  /// Returns `true` when [request] is approved by one of the configured
  /// auto-approval rules. Rules are evaluated in order; the first rule
  /// returning `true` wins.
  ///
  /// [requestMessages] are the messages sent to the inner agent for the turn
  /// that produced [request]; they are handed to each rule along with
  /// [session] and [options].
  Future<bool> matchesAutoApprovalRule(
    ToolApprovalRequestContent request, {
    AgentSession? session,
    AgentRunOptions? options,
    Iterable<ChatMessage> requestMessages = const [],
  }) async {
    final rules = _autoApprovalRules;
    if (rules == null || rules.isEmpty) {
      return false;
    }
    final toolCall = _asFunctionCall(request.toolCall);
    if (toolCall == null) {
      return false;
    }
    final context = ToolAutoApprovalRuleContext(
      functionCallContent: toolCall,
      agent: this,
      session: session,
      requestMessages: requestMessages,
      runOptions: options,
    );
    for (final rule in rules) {
      if (await rule(context)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final inbound = await prepareInboundMessages(
      messages,
      session,
      options: options,
    );
    final state = inbound.state;
    var callerMessages = inbound.callerMessages;

    if (inbound.nextQueuedItem != null) {
      return AgentResponse(
        message: ChatMessage(
          role: ChatRole.assistant,
          contents: [inbound.nextQueuedItem!],
        ),
      );
    }

    // Usage is accumulated across every re-invocation so the caller sees the
    // token cost of the whole run, not just its final inner call.
    UsageDetails? aggregatedUsage;

    for (var iteration = 0; ; iteration++) {
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

      aggregatedUsage = UsageAggregator.combine(
        aggregatedUsage,
        response.usage,
      );

      if (iteration >= _maxAutoApprovalIterations) {
        // Cap reached: this turn is returned as-is, so any approval request it
        // surfaces goes to the caller to decide rather than continuing the
        // auto-approval chain. Those requests are recorded as surfaced so a
        // legitimate always-approve response to them can be bound. The usage
        // reported still covers every prior turn of the run rather than only
        // this final one.
        recordSurfacedApprovalRequestsFromMessages(
          response.messages,
          state,
          session,
        );
        return response.applyAggregatedUsage(aggregatedUsage);
      }

      final allAutoApproved = await processAndQueueOutboundApprovalRequests(
        response.messages,
        state,
        session,
        options: options,
        requestMessages: processedMessages,
      );
      if (!allAutoApproved) {
        return response.applyAggregatedUsage(aggregatedUsage);
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
    final inbound = await prepareInboundMessages(
      messages,
      session,
      options: options,
    );
    final state = inbound.state;
    var callerMessages = inbound.callerMessages;

    if (inbound.nextQueuedItem != null) {
      yield AgentResponseUpdate(
        role: ChatRole.assistant,
        contents: [inbound.nextQueuedItem!],
      );
      return;
    }

    for (var iteration = 0; ; iteration++) {
      final processedMessages = injectCollectedResponses(
        callerMessages,
        state,
        session,
      );
      final streamedApprovalRequests = <ToolApprovalRequestContent>[];

      // Cap reached: this turn streams through untouched, so any approval
      // request it surfaces goes to the caller to decide rather than
      // continuing the auto-approval chain.
      final capped = iteration >= _maxAutoApprovalIterations;

      // On a capped turn the requests reach the caller, so they are recorded
      // as surfaced for a legitimate always-approve response to bind against.
      var recordedAnyCappedRequest = false;

      await for (final update in innerAgent.runStreaming(
        session,
        options,
        cancellationToken: cancellationToken,
        messages: processedMessages,
      )) {
        if (capped) {
          // Record before yielding: a consumer may stop listening as soon as
          // it sees an approval request, which cancels this subscription and
          // skips anything after the loop. The record must already be in
          // place by the time the caller can act on the request.
          final cappedRequests = update.contents
              .whereType<ToolApprovalRequestContent>()
              .toList();
          if (cappedRequests.isNotEmpty) {
            // The first update carrying requests supersedes any earlier
            // batch; later updates in this same turn add to it, since every
            // one of them reaches the caller.
            if (recordedAnyCappedRequest) {
              for (final request in cappedRequests) {
                recordSurfacedApprovalRequest(state, request);
              }
            } else {
              resetSurfacedApprovalRequests(state, cappedRequests);
              recordedAnyCappedRequest = true;
            }
            _sessionState.saveState(session, state);
          }
        }

        final approvalRequests = capped
            ? const <ToolApprovalRequestContent>[]
            : update.contents.whereType<ToolApprovalRequestContent>().toList();
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
        } else if (await matchesAutoApprovalRule(
          request,
          session: session,
          options: options,
          requestMessages: processedMessages,
        )) {
          state.collectedApprovalResponses.add(
            request.createResponse(
              true,
              reason: 'Auto-approved by auto-approval rule',
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

      // Only the yielded request is recorded as surfaced; queued requests are
      // recorded when they are later dequeued and presented.
      resetSurfacedApprovalRequests(state, [unapproved.first]);

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

  Future<
    ({
      ToolApprovalState state,
      List<ChatMessage> callerMessages,
      ToolApprovalRequestContent? nextQueuedItem,
    })
  >
  prepareInboundMessages(
    Iterable<ChatMessage> messages,
    AgentSession? session, {
    AgentRunOptions? options,
  }) async {
    final state = _sessionState.getOrInitializeState(session);

    // During a queue cycle the caller's messages are not forwarded to the
    // inner agent on this turn, so a bound response must be collected into
    // state instead of being left in the messages.
    final queueCycleActive = state.queuedApprovalRequests.isNotEmpty;

    final callerMessages = bindApprovalResponses(
      messages,
      state,
      _jsonSerializerOptions,
      collectBoundResponses: queueCycleActive,
    );

    if (queueCycleActive) {
      await drainAutoApprovableFromQueue(
        state,
        session: session,
        options: options,
        requestMessages: callerMessages,
      );
      if (state.queuedApprovalRequests.isNotEmpty) {
        final next = state.queuedApprovalRequests.removeAt(0);

        // Record it as surfaced only now that it is actually being presented,
        // so a response cannot be bound to a request the caller has not yet
        // seen.
        recordSurfacedApprovalRequest(state, next);

        _sessionState.saveState(session, state);
        return (
          state: state,
          callerMessages: callerMessages,
          nextQueuedItem: next,
        );
      }

      _sessionState.saveState(session, state);
    }

    return (state: state, callerMessages: callerMessages, nextQueuedItem: null);
  }

  Future<void> drainAutoApprovableFromQueue(
    ToolApprovalState state, {
    AgentSession? session,
    AgentRunOptions? options,
    Iterable<ChatMessage> requestMessages = const [],
  }) async {
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
      } else if (await matchesAutoApprovalRule(
        request,
        session: session,
        options: options,
        requestMessages: requestMessages,
      )) {
        state.collectedApprovalResponses.add(
          request.createResponse(
            true,
            reason: 'Auto-approved by auto-approval rule',
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

  Future<bool> processAndQueueOutboundApprovalRequests(
    List<ChatMessage> responseMessages,
    ToolApprovalState state,
    AgentSession? session, {
    AgentRunOptions? options,
    Iterable<ChatMessage> requestMessages = const [],
  }) async {
    final autoApproved = <ToolApprovalRequestContent>[];
    final unapproved = <ToolApprovalRequestContent>[];

    for (final message in responseMessages) {
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          if (matchesRule(content, state.rules, _jsonSerializerOptions)) {
            autoApproved.add(content);
          } else if (await matchesAutoApprovalRule(
            content,
            session: session,
            options: options,
            requestMessages: requestMessages,
          )) {
            autoApproved.add(content);
          } else {
            unapproved.add(content);
          }
        }
      }
    }

    if (autoApproved.isEmpty && unapproved.length <= 1) {
      // The single unapproved request is still returned to the caller, so
      // record it as surfaced. Without this, a legitimate always-approve
      // response to it could not be bound.
      if (unapproved.length == 1) {
        resetSurfacedApprovalRequests(state, unapproved);
        _sessionState.saveState(session, state);
      }

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

    // Only the first unapproved request is returned to the caller now, so
    // only it is surfaced. Queued requests are recorded when they are later
    // dequeued and presented.
    resetSurfacedApprovalRequests(state, [unapproved.first]);

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

  /// Scans inbound messages for tool approval responses — plain
  /// [ToolApprovalResponseContent] and
  /// [AlwaysApproveToolApprovalResponseContent] wrappers alike — and binds
  /// each one to an approval request this agent actually surfaced, before any
  /// standing rule is recorded.
  ///
  /// A response is bound only when its request id matches a request recorded
  /// in [ToolApprovalState.surfacedApprovalRequests]. The matched request is
  /// consumed, and both the forwarded response and any standing rule are
  /// derived from the *recorded* tool call rather than the caller-supplied
  /// one, so a caller cannot widen an approval by substituting a different
  /// tool name or arguments.
  ///
  /// This is the single place a surfaced request is consumed, and it runs on
  /// every inbound pass. Plain responses must consume their request too:
  /// otherwise a request answered once would stay eligible for binding,
  /// letting a caller replay the same id as a wrapper to promote a one-time
  /// approval into a standing rule, or to overturn a denial with an approval.
  ///
  /// A response that cannot be bound creates no standing rule. A wrapper is
  /// downgraded to the plain approval response it carries, and a plain
  /// response is forwarded unchanged, for the approval-binding chat client to
  /// validate against its own record. This is deliberate: an unbound response
  /// is produced both by a forgery and by legitimate cases such as replaying a
  /// transcript into a new session, so the two are treated identically and
  /// safely rather than one of them failing the run. Unbound responses are
  /// never dropped here.
  ///
  /// When [collectBoundResponses] is `true` a bound response is moved into
  /// [ToolApprovalState.collectedApprovalResponses] for injection once the
  /// queue resolves, instead of being left in the messages. That is used
  /// during a queue cycle, where the caller's messages are not forwarded to
  /// the inner agent on this turn.
  static List<ChatMessage> bindApprovalResponses(
    Iterable<ChatMessage> messages,
    ToolApprovalState state,
    JsonSerializerOptions jsonSerializerOptions, {
    required bool collectBoundResponses,
  }) {
    final messageList = List<ChatMessage>.of(messages);
    var anyModified = false;
    final result = <ChatMessage>[];

    for (final message in messageList) {
      if (!message.contents.any(
        (c) =>
            c is ToolApprovalResponseContent ||
            c is AlwaysApproveToolApprovalResponseContent,
      )) {
        result.add(message);
        continue;
      }

      final newContents = <AIContent>[];
      for (final content in message.contents) {
        // Unwrap so plain and wrapped responses share one binding decision.
        // Only a wrapper can carry a standing rule, so the wrapper itself is
        // kept to consult its flags after binding.
        final alwaysApprove =
            content is AlwaysApproveToolApprovalResponseContent
            ? content
            : null;
        final innerResponse =
            alwaysApprove?.innerResponse ??
            (content is ToolApprovalResponseContent ? content : null);

        if (innerResponse == null) {
          newContents.add(content);
          continue;
        }

        // Security boundary: an approval may only be honored against a
        // request this agent surfaced and is still awaiting a response for.
        // Remove on match so a surfaced request authorizes at most one
        // response.
        final surfacedRequest = state.surfacedApprovalRequests.remove(
          innerResponse.requestId,
        );
        if (surfacedRequest == null) {
          newContents.add(innerResponse);
          if (alwaysApprove != null) {
            anyModified = true;
          }
          continue;
        }

        // Rebind to the recorded tool call so the approved call is exactly
        // what was surfaced.
        final boundResponse = ToolApprovalResponseContent(
          requestId: innerResponse.requestId,
          approved: innerResponse.approved,
          toolCall: surfacedRequest.toolCall,
          reason: innerResponse.reason,
        );

        // Only an approval carried by a wrapper creates a standing rule. A
        // denial, or a plain response answering only this one request, is a
        // legitimate answer that records nothing.
        if (alwaysApprove != null && innerResponse.approved) {
          final recordedCall = _asFunctionCall(surfacedRequest.toolCall);
          if (recordedCall != null) {
            if (alwaysApprove.alwaysApproveTool) {
              addRuleIfNotExists(
                state,
                ToolApprovalRule(toolName: recordedCall.name),
              );
            } else if (alwaysApprove.alwaysApproveToolWithArguments) {
              addRuleIfNotExists(
                state,
                ToolApprovalRule(
                  toolName: recordedCall.name,
                  arguments: serializeArguments(
                    recordedCall.arguments,
                    jsonSerializerOptions,
                  ),
                ),
              );
            }
          }
        }

        if (collectBoundResponses) {
          // Queue cycle: hold the response for injection once every queued
          // request is resolved.
          state.collectedApprovalResponses.add(boundResponse);
        } else {
          newContents.add(boundResponse);
        }
        anyModified = true;
      }

      // A message left empty by collecting its responses is dropped.
      if (newContents.isNotEmpty) {
        result.add(_cloneMessageWithContents(message, newContents));
      } else {
        anyModified = true;
      }
    }

    return anyModified ? result : messageList;
  }

  /// Replaces the recorded set of surfaced approval requests with a new batch
  /// returned by the inner agent.
  ///
  /// A new batch supersedes any previous one, so stale entries from an
  /// abandoned approval cycle cannot later authorize a standing rule.
  ///
  /// Upstream stores a defensive snapshot of each request here. That is not
  /// reproducible in this port for the same reason the approval-binding chat
  /// client cannot snapshot (see PORTING.md, 2026-08-13): `extensions` has no
  /// concrete tool call type carrying a function name and arguments, so the
  /// recorded call cannot be rebuilt. Requests are recorded as-is.
  static void resetSurfacedApprovalRequests(
    ToolApprovalState state,
    List<ToolApprovalRequestContent> requests,
  ) {
    state.surfacedApprovalRequests
      ..clear()
      ..addEntries(
        requests.map((request) => MapEntry(request.requestId, request)),
      );
  }

  /// Records a single approval request as surfaced to the caller.
  ///
  /// Used when dequeuing a previously queued request. Existing entries are
  /// preserved because every request in an in-flight queue cycle belongs to
  /// the same batch and may still be awaiting a response.
  static void recordSurfacedApprovalRequest(
    ToolApprovalState state,
    ToolApprovalRequestContent request,
  ) {
    state.surfacedApprovalRequests[request.requestId] = request;
  }

  /// Records every [ToolApprovalRequestContent] found in [responseMessages]
  /// as surfaced to the caller.
  ///
  /// Used when a response is handed back without approval processing (the
  /// auto-approval cap path), where the requests still reach the caller and
  /// must therefore be bindable.
  void recordSurfacedApprovalRequestsFromMessages(
    List<ChatMessage> responseMessages,
    ToolApprovalState state,
    AgentSession? session,
  ) {
    final requests = <ToolApprovalRequestContent>[
      for (final message in responseMessages)
        for (final content in message.contents)
          if (content is ToolApprovalRequestContent) content,
    ];

    if (requests.isNotEmpty) {
      resetSurfacedApprovalRequests(state, requests);
      _sessionState.saveState(session, state);
    }
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
