import 'dart:math';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../func_typedefs.dart';
import '../../../ai/microsoft_agents_ai/chat_client/chat_client_agent_run_options.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../handoff_tool_call_filtering_behavior.dart';
import '../handoff_workflow_builder.dart';
import '../protocol_builder.dart';
import '../workflow_context.dart';
import '../workflow_warning_event.dart';
import 'ai_content_external_handler.dart';
import 'handoff_start_executor.dart';
import 'handoff_state.dart';
import 'handoff_target.dart';
import '../../../json_stubs.dart';

class AgentInvocationResult {
  const AgentInvocationResult(
    AgentResponse agentResponse,
    String? handoffTargetId,
  ) : handoffTargetId = handoffTargetId;

  AgentResponse get response {
    return agentResponse;
  }

  String? get handoffTargetId {
    return handoffTargetId;
  }

  bool get isHandoffRequested {
    return this.handoffTargetId != null;
  }
}
/// Executor used to represent an agent in a handoffs workflow, responding to
/// [HandoffState] events.
class HandoffAgentExecutor extends StatefulExecutor<HandoffAgentHostState, HandoffState> {
  HandoffAgentExecutor(
    AIAgent agent,
    Set<HandoffTarget> handoffs,
    HandoffAgentExecutorOptions options,
  ) :
      _agent = agent,
      _options = options {
    this._agentOptions = createAgentHandoffContext(
      this._options.handoffInstructions,
      handoffs,
      this._handoffFunctionNames,
      this._handoffFunctionToAgentId,
    );
  }

  static final JsonElement s_handoffSchema;

  final AIAgent _agent;

  late final ChatClientAgentRunOptions? _agentOptions;

  final HandoffAgentExecutorOptions _options;

  final Set<String> _handoffFunctionNames = {};

  final Map<String, String> _handoffFunctionToAgentId = {};

  final StateRef<HandoffSharedState> _sharedStateRef;

  late AgentSession? _session;

  late AIContentExternalHandler<ToolApprovalRequestContent, ToolApprovalResponseContent>? _userInputHandler;

  late AIContentExternalHandler<FunctionCallContent, FunctionResultContent>? _functionCallHandler;

  static String idFor(AIAgent agent) {
    return agent.getDescriptiveId();
  }

  static HandoffAgentHostState initialStateFactory() {
    return new(null, 0);
  }

  static ChatClientAgentRunOptions? createAgentHandoffContext(
    String? handoffInstructions,
    Set<HandoffTarget> handoffs,
    Set<String> functionNames,
    Map<String, String> functionToAgentId,
  ) {
    var result = null;
    if (handoffs.length != 0) {
      result = new()
            {
                ChatOptions = new()
                {
                    AllowMultipleToolCalls = false,
                    Instructions = handoffInstructions,
                    Tools = [],
                },
            };
      var index = 0;
      for (final handoff in handoffs) {
        index++;
        var handoffFunc = AIFunctionFactory.createDeclaration(
          '${HandoffWorkflowBuilder.functionPrefix}${index}',
          handoff.reason,
          s_handoffSchema,
        );
        functionNames.add(handoffFunc.name);
        functionToAgentId[handoffFunc.name] = handoff.target.id;
        result.chatOptions.tools.add(handoffFunc);
      }
    }
    return result;
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return this.configureUserInputHandling(super.configureProtocol(protocolBuilder))
                   .sendsMessage<HandoffState>();
  }

  ProtocolBuilder configureUserInputHandling(ProtocolBuilder protocolBuilder) {
    this._userInputHandler = new AIContentExternalHandler<ToolApprovalRequestContent, ToolApprovalResponseContent>(
            protocolBuilder,
            portId: '${this.id}_UserInput',
            intercepted: false,
            handler: this.handleUserInputResponseAsync);
    this._functionCallHandler = new AIContentExternalHandler<FunctionCallContent, FunctionResultContent>(
            protocolBuilder,
            portId: '${this.id}_FunctionCall',
            intercepted: false, // TODO: Use this instead of manual function handling for handoff?
            handler: this.handleFunctionResultAsync);
    return protocolBuilder;
  }

  Future handleUserInputResponse(
    ToolApprovalResponseContent response,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    if (!this._userInputHandler!.markRequestAsHandled(response.requestId)) {
      throw StateError("No pending ToolApprovalRequest found with id ${response.requestId}.");
    }
    return this.invokeWithState((state, ctx, ct) =>
        {
            if (!state.isTakingTurn)
            {
                throw StateError("Cannot process user responses when not taking a turn in Handoff Orchestration.");
      }

            ChatMessage userMessage = new(ChatRole.user, [response])
            {
                CreatedAt = DateTime.now().toUtc(),
                MessageId = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join(),
            };

            return this.continueTurnAsync(state, [userMessage], ctx, ct);
        }, context, skipCache: false, cancellationToken);
  }

  Future handleFunctionResult(
    FunctionResultContent result,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    if (!this._functionCallHandler!.markRequestAsHandled(result.callId)) {
      throw StateError("No pending FunctionCall found with id ${result.callId}.");
    }
    return this.invokeWithState((state, ctx, ct) =>
        {
            if (!state.isTakingTurn)
            {
                throw StateError("Cannot process user responses in when not taking a turn in Handoff Orchestration.");
      }

            ChatMessage toolMessage = new(ChatRole.tool, [result])
            {
                AuthorName = this._agent.name ?? this._agent.id,
                CreatedAt = DateTime.now().toUtc(),
                MessageId = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join(),
            };

            return this.continueTurnAsync(state, [toolMessage], ctx, ct);
        }, context, skipCache: false, cancellationToken);
  }

  Future<HandoffAgentHostState?> continueTurn(
    HandoffAgentHostState state,
    List<ChatMessage> incomingMessages,
    WorkflowContext context,
    CancellationToken cancellationToken,
    {bool? skipAddIncoming, },
  ) async  {
    if (!state.isTakingTurn) {
      throw StateError("Cannot process user responses in when not taking a turn in Handoff Orchestration.");
    }
    var handoffMessagesFilter = new(this._options.toolCallFilteringBehavior);
    var messagesForAgent = state.incomingState.requestedHandoffTargetAgentId != null
                                                  ? handoffMessagesFilter.filterMessages(incomingMessages)
                                                  : incomingMessages;
    var roleChanges = messagesForAgent.changeAssistantToUserForOtherParticipants(this._agent.name ?? this._agent.id);
    var emitUpdateEvents = state.incomingState!.shouldEmitStreamingEvents(this._options.emitAgentResponseUpdateEvents);
    var result = await this.invokeAgentAsync(
      messagesForAgent,
      context,
      emitUpdateEvents,
      cancellationToken,
    )
                                                     ;
    if (this.hasOutstandingRequests && result.isHandoffRequested) {
      throw StateError("Cannot request a handoff while holding pending requests.");
    }
    roleChanges.resetUserToAssistantForChangedRoles();
    var newConversationBookmark = state.conversationBookmark;
    await this._sharedStateRef.invokeWithState(
            (sharedState, ctx, ct) =>
            {
                if (sharedState == null)
                {
                    throw StateError("Handoff Orchestration shared state was not properly initialized.");
      }

                if (!skipAddIncoming)
                {
                    sharedState.conversation.addMessages(incomingMessages);
      }

                newConversationBookmark = sharedState.conversation.addMessages(result.response.messages);

                return future();
            },
            context,
            cancellationToken);
    if (!this.hasOutstandingRequests) {
      var outgoingState = new(
        state.incomingState.turnToken,
        result.handoffTargetId,
        this._agent.id,
      );
      await context.sendMessage(outgoingState, cancellationToken);
      return state with { IncomingState = null, ConversationBookmark = newConversationBookmark };
    }
    return state;
  }

  @override
  Future handle(
    HandoffState message,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) {
    return this.invokeWithState(
      InvokeContinueTurnAsync,
      context,
      skipCache: false,
      cancellationToken,
    );
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<HandoffAgentHostState?> InvokeContinueTurnAsync(HandoffAgentHostState state, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             // Check that we are not getting this message while in the middle of a turn
      //             if (state.IsTakingTurn)
      //             {
        //                 throw new InvalidOperationException("Cannot have multiple simultaneous conversations in Handoff Orchestration.");
        //             }
      //
      //             Iterable<ChatMessage> newConversationMessages = [];
      //             int newConversationBookmark = 0;
      //
      //             await this._sharedStateRef.InvokeWithStateAsync(
      //                 (sharedState, ctx, ct) =>
      //                 {
        //                     if (sharedState == null)
        //                     {
          //                         throw new InvalidOperationException("Handoff Orchestration shared state was not properly initialized.");
          //                     }
        //
        //                     (newConversationMessages, newConversationBookmark) = sharedState.Conversation.CollectNewMessages(state.ConversationBookmark);
        //
        //                     return new ValueTask();
        //                 },
      //                 context,
      //                 cancellationToken);
      //
      //             state = state with { IncomingState = message, ConversationBookmark = newConversationBookmark };
      //
      //             return await this.ContinueTurnAsync(state, newConversationMessages.ToList(), context, cancellationToken, skipAddIncoming: true)
      //                              ;
      //         }
  }

  @override
  Future onCheckpointing(WorkflowContext context, {CancellationToken? cancellationToken, }) async  {
    var userInputRequestsTask = this._userInputHandler?.onCheckpointingAsync(
      UserInputRequestStateKey,
      context,
      cancellationToken,
    ) .future ?? Task.value(null);
    var functionCallRequestsTask = this._functionCallHandler?.onCheckpointingAsync(
      FunctionCallRequestStateKey,
      context,
      cancellationToken,
    ) .future ?? Task.value(null);
    var agentSessionTask = checkpointAgentSessionAsync();
    var baseTask = super.onCheckpointingAsync(context, cancellationToken).future;
    await Future.wait(
      userInputRequestsTask,
      functionCallRequestsTask,
      agentSessionTask,
      baseTask,
    ) ;
    /* TODO: unsupported node kind "unknown" */
    // async Task CheckpointAgentSessionAsync()
    //         {
      //             JsonElement? sessionState = this._session is not null ? await this._agent.SerializeSessionAsync(this._session, cancellationToken: cancellationToken) : null;
      //             await context.QueueStateUpdateAsync(AgentSessionKey, sessionState, cancellationToken: cancellationToken);
      //         }
  }

  @override
  Future onCheckpointRestored(
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    var userInputRestoreTask = this._userInputHandler?.onCheckpointRestoredAsync(
      UserInputRequestStateKey,
      context,
      cancellationToken,
    ) .future ?? Task.value(null);
    var functionCallRestoreTask = this._functionCallHandler?.onCheckpointRestoredAsync(
      FunctionCallRequestStateKey,
      context,
      cancellationToken,
    ) .future ?? Task.value(null);
    var agentSessionTask = restoreAgentSessionAsync();
    await Future.wait(
      userInputRestoreTask,
      functionCallRestoreTask,
      agentSessionTask,
    ) ;
    await super.onCheckpointRestoredAsync(context, cancellationToken);
    /* TODO: unsupported node kind "unknown" */
    // async Task RestoreAgentSessionAsync()
    //         {
      //             JsonElement? sessionState = await context.ReadStateAsync<JsonElement?>(AgentSessionKey, cancellationToken: cancellationToken);
      //             if (sessionState.HasValue)
      //             {
        //                 this._session = await this._agent.DeserializeSessionAsync(sessionState.Value, cancellationToken: cancellationToken);
        //             }
      //         }
  }

  bool get hasOutstandingRequests {
    return (this._userInputHandler?.hasPendingRequests == true)
                                        || (this._functionCallHandler?.hasPendingRequests == true);
  }

  Future<AgentInvocationResult> invokeAgent(
    Iterable<ChatMessage> messages,
    WorkflowContext context,
    bool emitUpdateEvents,
    {CancellationToken? cancellationToken, },
  ) async  {
    AgentResponse response;
    var collector = new(this._userInputHandler, this._functionCallHandler);
    var requestedHandoff = null;
    var updates = [];
    var candidateRequests = [];
    await this.invokeWithState(
            async (state, ctx, ct) =>
            {
                this._session ??= await this._agent.createSessionAsync(ct);

                Stream<AgentResponseUpdate> agentStream =
                    this._agent.runStreamingAsync(messages,
                                                  this._session,
                                                  options: this._agentOptions,
                                                  cancellationToken: ct);

                await foreach (AgentResponseUpdate update in agentStream)
                {
                    await addUpdateAsync(update, ct);

                    collector.processAgentResponseUpdate(update, CollectHandoffRequestsFilter);

                    bool collectHandoffRequestsFilter(FunctionCallContent candidateHandoffRequest)
                    {
                        bool isHandoffRequest = this._handoffFunctionNames.contains(candidateHandoffRequest.name);
                        if (isHandoffRequest)
                        {
                            candidateRequests.add(candidateHandoffRequest);
          }

                        return !isHandoffRequest;
        }
      }

                return state;
            },
            context,
            cancellationToken: cancellationToken);
    if (candidateRequests.length > 1) {
      var message = 'Duplicate handoff requests in single turn ([${candidateRequests.map((request.join(", ") => request.name))}]). Using last (${candidateRequests.last().name})';
      await context.addEvent(
        workflowWarningEvent(message),
        cancellationToken,
      ) ;
    }
    if (candidateRequests.length > 0) {
      var handoffRequest = candidateRequests[candidateRequests.length - 1];
      requestedHandoff = handoffRequest.name;
      await addUpdateAsync(
                    AgentResponseUpdate(),
                    cancellationToken
                 )
                ;
    }
    response = updates.toAgentResponse();
    if (this._options.emitAgentResponseEvents) {
      await context.yieldOutput(response, cancellationToken);
    }
    await collector.submitAsync(context, cancellationToken);
    return new(response, lookupHandoffTarget(requestedHandoff));
    /* TODO: unsupported node kind "unknown" */
    // ValueTask AddUpdateAsync(AgentResponseUpdate update, CancellationToken cancellationToken)
    //         {
      //             updates.Add(update);
      //
      //             return emitUpdateEvents ? context.YieldOutputAsync(update, cancellationToken) : default;
      //         }
    /* TODO: unsupported node kind "unknown" */
    // String? LookupHandoffTarget(String? requestedHandoff)
    //             => requestedHandoff != null
    //              ? this._handoffFunctionToAgentId.TryGetValue(requestedHandoff, targetId) ? targetId : null
    //              : null;
  }

  static FunctionResultContent createHandoffResult(String requestCallId) {
    return new(requestCallId, "Transferred.");
  }
}
class HandoffAgentExecutorOptions {
  HandoffAgentExecutorOptions(
    String? handoffInstructions,
    bool emitAgentResponseEvents,
    bool? emitAgentResponseUpdateEvents,
    HandoffToolCallFilteringBehavior toolCallFilteringBehavior,
  ) :
      handoffInstructions = handoffInstructions,
      emitAgentResponseEvents = emitAgentResponseEvents,
      emitAgentResponseUpdateEvents = emitAgentResponseUpdateEvents,
      toolCallFilteringBehavior = toolCallFilteringBehavior {
  }

  String? handoffInstructions;

  bool emitAgentResponseEvents;

  bool? emitAgentResponseUpdateEvents;

  HandoffToolCallFilteringBehavior toolCallFilteringBehavior = HandoffToolCallFilteringBehavior.HandoffOnly;

}
class HandoffAgentHostState {
  const HandoffAgentHostState(
    HandoffState? IncomingState,
    int ConversationBookmark,
  ) :
      incomingState = IncomingState,
      conversationBookmark = ConversationBookmark;

  HandoffState? incomingState;

  int conversationBookmark;

  bool get isTakingTurn {
    return this.incomingState != null;
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is HandoffAgentHostState &&
    incomingState == other.incomingState &&
    conversationBookmark == other.conversationBookmark; }
  @override
  int get hashCode { return Object.hash(incomingState, conversationBookmark); }
}
class StateRef<TState> {
  const StateRef(String Key, String? ScopeName, ) : key = Key, scopeName = ScopeName;

  String key;

  String? scopeName;

  Future invokeWithState(
    WorkflowContext context,
    CancellationToken cancellationToken,
    {Func3<TState?, WorkflowContext, CancellationToken, Future<TState?>>? invocation, },
  ) {
    return context.invokeWithState(invocation, this.key, this.scopeName, cancellationToken);
  }
}
