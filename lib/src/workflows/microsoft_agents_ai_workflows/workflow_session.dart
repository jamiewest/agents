import 'dart:math';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'agent_response_update_event.dart';
import 'checkpoint_info.dart';
import 'checkpoint_manager.dart';
import 'checkpointing/in_memory_checkpoint_manager.dart';
import 'external_request.dart';
import 'external_response.dart';
import 'in_proc/in_process_execution_environment.dart';
import 'portable_value.dart';
import 'request_info_event.dart';
import 'streaming_run.dart';
import 'super_step_completed_event.dart';
import 'turn_token.dart';
import 'workflow.dart';
import 'workflow_chat_history_provider.dart';
import 'workflow_error_event.dart';
import 'workflow_execution_environment.dart';
import 'workflow_output_event.dart';
import '../../json_stubs.dart';
import '../../map_extensions.dart';

class WorkflowSession extends AgentSession {
  WorkflowSession(
    Workflow workflow,
    WorkflowExecutionEnvironment executionEnvironment,
    bool includeExceptionDetails,
    bool includeWorkflowOutputsInResponse,
    {String? sessionId = null, JsonElement? serializedSession = null, JsonSerializerOptions? JsonSerializerOptions = null, },
  ) :
      _workflow = workflow,
      _includeExceptionDetails = includeExceptionDetails,
      _includeWorkflowOutputsInResponse = includeWorkflowOutputsInResponse {
    var env = executionEnvironment;
    {
      InProcessExecutionEnvironment? inProcEnv;
      if (verifyCheckpointingConfiguration(env)) {
        // We have an InProcessExecutionEnvironment which is! configured for checkpointing. Ensure it has an externalizable checkpoint manager,
            // since we are responsible for maintaining the state.
            env = inProcEnv.withCheckpointing(this.ensureExternalizedInMemoryCheckpointing());
      }
    }
    this._inProcEnvironment = env as InProcessExecutionEnvironment
            ?? throw StateError(
                'WorkflowSession requires an ${'InProcessExecutionEnvironment'}, ' +
                'but received ${env.runtimeType.toString()}.');
    this.sessionId = sessionId;
    this.chatHistoryProvider = workflowChatHistoryProvider();
  }

  final Workflow _workflow;

  /// The execution environment for this session. Concrete type is required
  /// because [CancellationToken)] uses the internal [CancellationToken)] API.
  late final InProcessExecutionEnvironment _inProcEnvironment;

  final bool _includeExceptionDetails;

  final bool _includeWorkflowOutputsInResponse;

  InMemoryCheckpointManager? _inMemoryCheckpointManager;

  /// Tracks pending external requests by their workflow-facing request ID. This
  /// mapping enables converting incoming response content back to
  /// [ExternalResponse] when resuming a workflow from a checkpoint.
  ///
  /// Remarks: Entries are added when a [RequestInfoEvent] is received during
  /// workflow execution, and removed when a matching response is delivered via
  /// [List{ChatMessage})]. The number of entries is bounded by the number of
  /// outstanding external requests in a single workflow run. When a session is
  /// abandoned, all pending requests are released with the session Object.
  /// Request-level timeouts, if needed, should be implemented in the workflow
  /// definition itself (e.g., using a timer racing against an external event).
  final Map<String, ExternalRequest> _pendingRequests = [];

  late CheckpointInfo? lastCheckpoint;

  late String? lastResponseId;

  late final String sessionId;

  late final WorkflowChatHistoryProvider chatHistoryProvider;

  static (
    bool,
    InProcessExecutionEnvironment??,
  ) verifyCheckpointingConfiguration(WorkflowExecutionEnvironment executionEnvironment) {
    var inProcEnv = null;
    inProcEnv = null;
    if (executionEnvironment.isCheckpointingEnabled) {
      return (false, inProcEnv);
    }
    if ((inProcEnv = executionEnvironment as InProcessExecutionEnvironment) == null) {
      throw StateError("Cannot use a non-checkpointed execution environment. Implicit checkpointing is supported only for InProcess.");
    }
    return (true, inProcEnv);
  }

  CheckpointManager ensureExternalizedInMemoryCheckpointing() {
    return new(this._inMemoryCheckpointManager ??= new());
  }

  JsonElement serialize({JsonSerializerOptions? JsonSerializerOptions}) {
    var marshaller = new(JsonSerializerOptions);
    var info = new(
            this.sessionId,
            this.lastCheckpoint,
            this._inMemoryCheckpointManager,
            this.stateBag,
            this._pendingRequests);
    return marshaller.marshal(info);
  }

  AgentResponseUpdate createUpdate(
    String responseId,
    Object raw,
    {List<AIContent>? parts, ChatMessage? message, },
  ) {
    return new(ChatRole.assistant, parts)
        {
            CreatedAt = DateTime.now().toUtc(),
            MessageId = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join(),
            Role = ChatRole.assistant,
            ResponseId = responseId,
            RawRepresentation = raw
        };
  }

  Future<ResumeRunResult> createOrResumeRun(
    List<ChatMessage> messages,
    {CancellationToken? cancellationToken, },
  ) async  {
    if (this.lastCheckpoint != null) {
      var run = await this._inProcEnvironment
                            .resumeStreamingInternalAsync(this._workflow,
                                               this.lastCheckpoint,
                                               republishPendingEvents: false,
                                               cancellationToken)
                            ;
      var dispatchInfo = await this.sendMessagesWithResponseConversionAsync(
        run,
        messages,
      ) ;
      return resumeRunResult(run, dispatchInfo);
    }
    var newRun = await this._inProcEnvironment
                            .runStreamingAsync(this._workflow,
                                         messages,
                                         this.sessionId,
                                         cancellationToken)
                            ;
    return resumeRunResult(newRun);
  }

  /// Sends messages to the run, converting FunctionResultContent and
  /// UserInputResponseContent to ExternalResponse when there's a matching
  /// pending request.
  ///
  /// Returns: Structured information ahow resume content was dispatched.
  Future<ResumeDispatchInfo> sendMessagesWithResponseConversion(
    StreamingRun run,
    List<ChatMessage> messages,
  ) async  {
    var regularMessages = [];
    var externalResponses = [];
    var hasMatchedResponseForStartExecutor = false;
    var matchedContentIds = null;
    for (final message in messages) {
      var regularContents = [];
      for (final content in message.contents) {
        var contentId = getResponseContentId(content);
        if (contentId != null && matchedContentIds?.contains(contentId) == true) {
          continue;
        }
        if (contentId != null
                    && this.tryGetPendingRequest(contentId) is ExternalRequest pendingRequest) {
          String? responseExecutorId;
          if (run.tryGetResponsePortExecutorId(pendingRequest.portInfo.portId)) {
            hasMatchedResponseForStartExecutor |= (responseExecutorId == this._workflow.startExecutorId,
              ,);
          }
          var normalizedResponseContent = normalizeResponseContentForDelivery(
            content,
            pendingRequest,
          );
          externalResponses.add((pendingRequest.createResponse(normalizedResponseContent), pendingRequest.requestId));
          (matchedContentIds ??= new()).add(contentId);
        } else {
          regularContents.add(content);
        }
      }
      if (regularContents.length > 0) {
        var cloned = message.clone();
        cloned.contents = regularContents;
        regularMessages.add(cloned);
      }
    }
    var hasRegularMessages = regularMessages.length > 0;
    if (hasRegularMessages) {
      await run.trySendMessageAsync(regularMessages);
    }
    var hasMatchedExternalResponses = false;
    /* TODO: unsupported node kind "unknown" */
    // foreach ((ExternalResponse response, String requestId) in externalResponses)
    //         {
      //             await run.SendResponseAsync(response);
      //             hasMatchedExternalResponses = true;
      //             this.RemovePendingRequest(requestId);
      //         }
    return resumeDispatchInfo(
            hasRegularMessages,
            hasMatchedExternalResponses,
            hasMatchedResponseForStartExecutor);
  }

  /// Creates the workflow-facing request content surfaced in response updates.
  static AIContent createRequestContentForDelivery(ExternalRequest request) {
    return request switch
    {
        ExternalRequest externalRequest when externalRequest.tryGetDataAs(functionCallContent)
            => cloneFunctionCallContent(functionCallContent, externalRequest.requestId),
        ExternalRequest externalRequest when externalRequest.tryGetDataAs(toolApprovalRequestContent)
            => cloneToolApprovalRequestContent(
              toolApprovalRequestContent,
              externalRequest.requestId,
            ),
        ExternalRequest (externalRequest) => externalRequest.toFunctionCall(),
    };
  }

  /// Rewrites workflow-facing response content back to the original agent-owned
  /// content ID.
  static Object normalizeResponseContentForDelivery(AIContent content, ExternalRequest request, ) {
    switch (content) {
      case FunctionResultContent functionResultContent:
      return cloneFunctionResultContent(functionResultContent, functionCallContent.callId);
      case FunctionResultContent functionResultContent:
      {
        var result = functionResultContent.result;
        if (result != null) {
          if (request.portInfo.responseType.isMatchPolymorphic(result.runtimeType) || result is PortableValue) {
            return result;
          }
          throw StateError('Unexpected result type in FunctionResultContent ${result.runtimeType}; expecting ${request.portInfo.responseType}');
        }
        throw UnsupportedError('Null result is! supported when using RequestPort with non-AIContent-typed requests. ${functionResultContent}');
      }
      case ToolApprovalResponseContent toolApprovalResponseContent:
      return cloneToolApprovalResponseContent(
        toolApprovalResponseContent,
        toolApprovalRequestContent.requestId,
      );
      default:
      return content;
    }
  }

  /// Gets the workflow-facing request ID from response content types.
  static String? getResponseContentId(AIContent content) {
    return content switch
    {
        FunctionResultContent (functionResultContent) => functionResultContent.callId,
        ToolApprovalResponseContent (toolApprovalResponseContent) => toolApprovalResponseContent.requestId,
        (_) => null
    };
  }

  /// Tries to get a pending request by workflow-facing request ID.
  ExternalRequest? tryGetPendingRequest(String requestId) {
    return this._pendingRequests.tryGetValue(
      requestId) ? request : null;
  }

  /// Adds a pending request indexed by workflow-facing request ID.
  void addPendingRequest(String requestId, ExternalRequest request, ) {
    this._pendingRequests[requestId] = request;
  }

  /// Removes a pending request by workflow-facing request ID.
  void removePendingRequest(String requestId) {
    this._pendingRequests.remove(requestId);
  }

  Stream<AgentResponseUpdate> invokeStage({CancellationToken? cancellationToken}) async  {
    this.lastResponseId = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    var messages = this.chatHistoryProvider.getFromBookmark(this).toList();
    var resumeResult = await this.createOrResumeRunAsync(
      messages,
      cancellationToken,
    ) ;
    var run = resumeResult.run;
    var dispatchInfo = resumeResult.dispatchInfo;
    var shouldSendTurnToken = !dispatchInfo.hasMatchedExternalResponses
            || !dispatchInfo.hasMatchedResponseForStartExecutor;
    if (shouldSendTurnToken) {
      await run.trySendMessageAsync(turnToken(emitEvents: true));
    }
    for (final evt in run.watchStreamAsync(blockOnPendingRequest: false, cancellationToken)
                                               
                                               .withCancellation(cancellationToken)) {
      switch (evt) {
        case AgentResponseUpdateEvent agentUpdate:
        yield agentUpdate.update;
        case RequestInfoEvent requestInfo:
        var requestContent = createRequestContentForDelivery(requestInfo.request);
        // Track the pending request so we can convert incoming responses back to ExternalResponse.
                    // External callers respond using the workflow-facing request ID, which is always RequestId.
                    this.addPendingRequest(requestInfo.request.requestId, requestInfo.request);
        var update = this.createUpdate(this.lastResponseId, evt, requestContent);
        yield update;
        case WorkflowErrorEvent workflowError:
        var exception = workflowError.exception;
        if (exception is TargetInvocationException tie && tie.innerException != null) {
          exception = tie.innerException;
        }
        if (exception != null) {
          var message = this._includeExceptionDetails
                                       ? exception.message
                                       : "An error occurred while executing the workflow.";
          var errorContent = new(message);
          yield this.createUpdate(this.lastResponseId, evt, errorContent);
        }
        case SuperStepCompletedEvent stepCompleted:
        this.lastCheckpoint = stepCompleted.completionInfo?.checkpoint;
        /* TODO: unsupported node kind "unknown" */
        // goto default;
        case WorkflowOutputEvent output:
        var updateMessages = output.data switch
                    {
                        Iterable<ChatMessage> (chatMessages) => chatMessages,
                        ChatMessage (chatMessage) => [chatMessage],
                        (_) => null
                    };
        if (!this._includeWorkflowOutputsInResponse || updateMessages == null) {
          /* TODO: unsupported node kind "unknown" */
          // goto default;
        }
        for (final message in updateMessages) {
          yield this.createUpdate(this.lastResponseId, evt, message);
        }
        default:
        yield AgentResponseUpdate(role: ChatRole.assistant, contents: []);
      }
    }
  }

  /// Clones a [FunctionCallContent] with a workflow-facing call ID.
  static FunctionCallContent cloneFunctionCallContent(
    FunctionCallContent content,
    String callId,
  ) {
    var clone = new(callId, content.name, content.arguments)
        {
            Exception = content.exception,
            InformationalOnly = content.informationalOnly,
        };
    return copyContentMetadata(content, clone);
  }

  /// Clones a [FunctionResultContent] with an agent-owned call ID.
  static FunctionResultContent cloneFunctionResultContent(
    FunctionResultContent content,
    String callId,
  ) {
    var clone = new(callId, content.result)
        {
            Exception = content.exception,
        };
    return copyContentMetadata(content, clone);
  }

  /// Clones a [ToolApprovalRequestContent] with a workflow-facing request ID.
  static ToolApprovalRequestContent cloneToolApprovalRequestContent(
    ToolApprovalRequestContent content,
    String id,
  ) {
    var clone = new(id, content.toolCall);
    return copyContentMetadata(content, clone);
  }

  /// Clones a [ToolApprovalResponseContent] with an agent-owned request ID.
  static ToolApprovalResponseContent cloneToolApprovalResponseContent(
    ToolApprovalResponseContent content,
    String id,
  ) {
    var clone = new(id, content.approved, content.toolCall)
        {
            Reason = content.reason,
        };
    return copyContentMetadata(content, clone);
  }

  /// Copies shared [AIContent] metadata to a cloned content instance.
  static TContent copyContentMetadata<TContent>(AIContent source, TContent target, ) {
    target.additionalProperties = source.additionalProperties;
    target.annotations = source.annotations;
    target.rawRepresentation = source.rawRepresentation;
    return target;
  }
}
/// Captures how resumed input was split across regular-message and
/// external-response delivery paths.
class ResumeDispatchInfo {
  ResumeDispatchInfo(
    bool hasRegularMessages,
    bool hasMatchedExternalResponses,
    bool hasMatchedResponseForStartExecutor,
  ) :
      hasRegularMessages = hasRegularMessages,
      hasMatchedExternalResponses = hasMatchedExternalResponses,
      hasMatchedResponseForStartExecutor = hasMatchedResponseForStartExecutor {
  }

  final bool hasRegularMessages;

  final bool hasMatchedExternalResponses;

  final bool hasMatchedResponseForStartExecutor;

}
/// Captures the outcome of creating or resuming a workflow run, indicating
/// what types of messages were sent during resume.
class ResumeRunResult {
  ResumeRunResult(StreamingRun run, {ResumeDispatchInfo? dispatchInfo = null, }) : run = run {
    this.dispatchInfo = dispatchInfo;
  }

  /// The streaming run that was created or resumed.
  final StreamingRun run;

  /// How resume-time content was dispatched into the workflow runtime.
  late final ResumeDispatchInfo dispatchInfo;

}
class SessionState {
  SessionState(
    String sessionId,
    CheckpointInfo? lastCheckpoint,
    {InMemoryCheckpointManager? checkpointManager = null, AgentSessionStateBag? stateBag = null, Map<String, ExternalRequest>? pendingRequests = null, },
  ) :
      sessionId = sessionId,
      lastCheckpoint = lastCheckpoint;

  final String sessionId = sessionId;

  final CheckpointInfo? lastCheckpoint = lastCheckpoint;

  final InMemoryCheckpointManager? checkpointManager = checkpointManager;

  final AgentSessionStateBag stateBag;

  final Map<String, ExternalRequest>? pendingRequests = pendingRequests;

}
