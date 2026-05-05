import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../ai_agent_host_options.dart';
import '../chat_protocol_executor.dart';
import '../protocol_builder.dart';
import '../turn_token.dart';
import '../workflow_context.dart';
import 'ai_content_external_handler.dart';
import 'handoff_state.dart';
import '../../../json_stubs.dart';

class AIAgentHostExecutor extends ChatProtocolExecutor {
  AIAgentHostExecutor(
    AIAgent agent,
    AIAgentHostOptions options,
  ) :
      _agent = agent,
      _options = options {
  }

  final AIAgent _agent;

  final AIAgentHostOptions _options;

  late AgentSession? _session;

  late bool? _currentTurnEmitEvents;

  late AIContentExternalHandler<ToolApprovalRequestContent, ToolApprovalResponseContent>? _userInputHandler;

  late AIContentExternalHandler<FunctionCallContent, FunctionResultContent>? _functionCallHandler;

  static final ChatProtocolExecutorOptions s_defaultChatProtocolOptions;

  ProtocolBuilder configureUserInputHandling(ProtocolBuilder protocolBuilder) {
    this._userInputHandler = new AIContentExternalHandler<ToolApprovalRequestContent, ToolApprovalResponseContent>(
            protocolBuilder,
            portId: '${this.id}_UserInput',
            intercepted: this._options.interceptUserInputRequests,
            handler: this.handleUserInputResponseAsync);
    this._functionCallHandler = new AIContentExternalHandler<FunctionCallContent, FunctionResultContent>(
            protocolBuilder,
            portId: '${this.id}_FunctionCall',
            intercepted: this._options.interceptUnterminatedFunctionCalls,
            handler: this.handleFunctionResultAsync);
    return protocolBuilder;
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return this.configureUserInputHandling(super.configureProtocol(protocolBuilder));
  }

  Future handleUserInputResponse(
    ToolApprovalResponseContent response,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    if (!this._userInputHandler!.markRequestAsHandled(response.requestId)) {
      throw StateError("No pending ToolApprovalRequest found with id ${response.requestId}.");
    }
    return this.processTurnMessagesAsync(async (pendingMessages, ctx, ct) =>
        {
            pendingMessages.add(ChatMessage(role: ChatRole.user, contents: [response]));

            await this.continueTurnAsync(
              pendingMessages,
              ctx,
              this._currentTurnEmitEvents ?? false,
              ct,
            ) ;

            // Clear the buffered turn messages because they were consumed by ContinueTurnAsync.
            return null;
        }, context, cancellationToken);
  }

  Future handleFunctionResult(
    FunctionResultContent result,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    if (!this._functionCallHandler!.markRequestAsHandled(result.callId)) {
      throw StateError("No pending FunctionCall found with id ${result.callId}.");
    }
    return this.processTurnMessagesAsync(async (pendingMessages, ctx, ct) =>
        {
            pendingMessages.add(ChatMessage(role: ChatRole.tool, contents: [result]));

            await this.continueTurnAsync(
              pendingMessages,
              ctx,
              this._currentTurnEmitEvents ?? false,
              ct,
            ) ;

            // Clear the buffered turn messages because they were consumed by ContinueTurnAsync.
            return null;
        }, context, cancellationToken);
  }

  Future<AgentSession> ensureSession(
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async  {
    return this._session ??= await this._agent.createSessionAsync(cancellationToken);
  }

  @override
  Future onCheckpointing(WorkflowContext context, {CancellationToken? cancellationToken, }) async  {
    var sessionState = this._session != null ? await this._agent.serializeSessionAsync(
      this._session,
      cancellationToken: cancellationToken,
    )  : null;
    var state = new(sessionState, this._currentTurnEmitEvents);
    var coreStateTask = context.queueStateUpdate(
      AIAgentHostStateKey,
      state,
      cancellationToken: cancellationToken,
    ) .future;
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
    var baseTask = super.onCheckpointingAsync(context, cancellationToken).future;
    await Future.wait(
      coreStateTask,
      userInputRequestsTask,
      functionCallRequestsTask,
      baseTask,
    ) ;
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
    var state = await context.readStateAsync<AIAgentHostState>(
      AIAgentHostStateKey,
      cancellationToken: cancellationToken,
    ) ;
    if (state != null) {
      this._session = state.threadState.hasValue
                         ? await this._agent.deserializeSessionAsync(
                           state.threadState.value,
                           cancellationToken: cancellationToken,
                         ) 
                         : null;
      this._currentTurnEmitEvents = state.currentTurnEmitEvents;
    }
    await Future.wait(userInputRestoreTask, functionCallRestoreTask);
    await super.onCheckpointRestoredAsync(context, cancellationToken);
  }

  bool get hasOutstandingRequests {
    return (this._userInputHandler?.hasPendingRequests == true)
                                        || (this._functionCallHandler?.hasPendingRequests == true);
  }

  Future continueTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    bool emitEvents,
    CancellationToken cancellationToken,
  ) async  {
    this._currentTurnEmitEvents = emitEvents;
    if (this._options.forwardIncomingMessages) {
      await context.sendMessage(messages, cancellationToken);
    }
    var filteredMessages = this._options.reassignOtherAgentsAsUsers
                                                  ? messages.map((m) => m.chatAssistantToUserIfNotFromNamed(this._agent.name ?? this._agent.id))
                                                  : messages;
    var response = await this.invokeAgentAsync(
      filteredMessages,
      context,
      emitEvents,
      cancellationToken,
    ) ;
    await context.sendMessage(
      response.messages is List<ChatMessage> list ? list : response.messages.toList(),
      cancellationToken,
    )
                     ;
    if (!this.hasOutstandingRequests) {
      await context.sendMessage(
        turnToken(this._currentTurnEmitEvents),
        cancellationToken,
      ) ;
      this._currentTurnEmitEvents = null;
    }
  }

  @override
  Future takeTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    bool? emitEvents,
    {CancellationToken? cancellationToken, },
  ) {
    return this.continueTurnAsync(messages,
                                  context,
                                  TurnExtensions.shouldEmitStreamingEvents(
                                    turnTokenSetting: emitEvents,
                                    this._options.emitAgentUpdateEvents,
                                  ),
                                  cancellationToken);
  }

  Future<AgentResponse> invokeAgent(
    Iterable<ChatMessage> messages,
    WorkflowContext context,
    bool emitUpdateEvents,
    {CancellationToken? cancellationToken, },
  ) async  {
    AgentResponse response;
    var collector = new(this._userInputHandler, this._functionCallHandler);
    if (emitUpdateEvents) {
      var agentStream = this._agent.runStreamingAsync(
                messages,
                await this.ensureSessionAsync(context, cancellationToken),
                cancellationToken: cancellationToken);
      var updates = [];
      for (final update in agentStream) {
        await context.yieldOutput(update, cancellationToken);
        collector.processAgentResponseUpdate(update);
        updates.add(update);
      }
      response = updates.toAgentResponse();
    } else {
      // Otherwise, run the agent in non-streaming mode.
            response = await this._agent.runAsync(messages,
                                                  await this.ensureSessionAsync(
                                                    context,
                                                    cancellationToken,
                                                  ) ,
                                                  cancellationToken: cancellationToken)
                                        ;
      collector.processAgentResponse(response);
    }
    if (this._options.emitAgentResponseEvents) {
      await context.yieldOutput(response, cancellationToken);
    }
    await collector.submitAsync(context, cancellationToken);
    return response;
  }
}
class AIAgentHostState {
  const AIAgentHostState(
    JsonElement? ThreadState,
    bool? CurrentTurnEmitEvents,
  ) :
      threadState = ThreadState,
      currentTurnEmitEvents = CurrentTurnEmitEvents;

  JsonElement? threadState;

  bool? currentTurnEmitEvents;

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is AIAgentHostState &&
    threadState == other.threadState &&
    currentTurnEmitEvents == other.currentTurnEmitEvents; }
  @override
  int get hashCode { return Object.hash(threadState, currentTurnEmitEvents); }
}
extension TurnExtensions on TurnToken {bool shouldEmitStreamingEvents({TurnToken? token, bool? turnTokenSetting, HandoffState? handoffState, }) {
return token.emitEvents ?? agentSetting ?? false;
 }
 }
