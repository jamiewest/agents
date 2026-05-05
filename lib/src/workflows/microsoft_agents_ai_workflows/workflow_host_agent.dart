import 'dart:math';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'in_proc/in_process_execution_environment.dart';
import 'in_process_execution.dart';
import 'protocol_descriptor.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';
import 'workflow_session.dart';
import '../../json_stubs.dart';

class WorkflowHostAgent extends AIAgent {
  WorkflowHostAgent(
    Workflow workflow,
    {String? id = null, String? name = null, String? description = null, WorkflowExecutionEnvironment? executionEnvironment = null, bool? includeExceptionDetails = null, bool? includeWorkflowOutputsInResponse = null, },
  ) : _workflow = workflow {
    this._executionEnvironment = executionEnvironment ?? (workflow.allowConcurrent
                                                              ? InProcessExecution.concurrent
                                                              : InProcessExecution.offThread);
    if (!this._executionEnvironment.isCheckpointingEnabled &&
             this._executionEnvironment is! InProcessExecutionEnvironment) {
      throw StateError("Cannot use a non-checkpointed execution environment. Implicit checkpointing is supported only for InProcess.");
    }
    this._includeExceptionDetails = includeExceptionDetails;
    this._includeWorkflowOutputsInResponse = includeWorkflowOutputsInResponse;
    this._id = id;
    this.name = name;
    this.description = description;
    // Kick off the typecheck right away by starting the DescribeProtocol task.
        this._describeTask = this._workflow.describeProtocolAsync().future;
  }

  final Workflow _workflow;

  late final String? _id;

  late final WorkflowExecutionEnvironment _executionEnvironment;

  late final bool _includeExceptionDetails;

  late final bool _includeWorkflowOutputsInResponse;

  final Future<ProtocolDescriptor> _describeFuture;

  final Map<String, String> _assignedSessionIds = {};

  late final String? name;

  late final String? description;

  String? get idCore {
    return this._id;
  }

  String generateNewId() {
    String result;
    do {
      result = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    } while (!this._assignedSessionIds.tryAdd(result, result));
    return result;
  }

  Future validateWorkflow() async  {
    var protocol = await this._describeTask;
    protocol.throwIfNotChatProtocol(allowCatchAll: true);
  }

  @override
  Future<AgentSession> createSessionCore({CancellationToken? cancellationToken}) {
    return new(WorkflowSession(this._workflow, this.generateNewId(), this._executionEnvironment, this._includeExceptionDetails, this._includeWorkflowOutputsInResponse));
  }

  @override
  Future<JsonElement> serializeSessionCore(
    AgentSession session,
    {JsonSerializerOptions? JsonSerializerOptions, CancellationToken? cancellationToken, },
  ) {
    _ = session;
    if (session is! WorkflowSession WorkflowSession) {
      throw StateError("The provided session type ${session.runtimeType.toString()} is! compatible with this agent. Only sessions of type "${'WorkflowSession'}' can be serialized by this agent.');
    }
    return new(WorkflowSession.serialize(JsonSerializerOptions));
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    JsonElement serializedState,
    {JsonSerializerOptions? JsonSerializerOptions, CancellationToken? cancellationToken, },
  ) {
    return new(WorkflowSession(this._workflow, serializedState, this._executionEnvironment, this._includeExceptionDetails, this._includeWorkflowOutputsInResponse, JsonSerializerOptions));
  }

  Future<WorkflowSession> updateSession(
    Iterable<ChatMessage> messages,
    {AgentSession? session, CancellationToken? cancellationToken, },
  ) async  {
    session ??= await this.createSessionAsync(cancellationToken);
    if (session is! WorkflowSession WorkflowSession) {
      throw ArgumentError(
        'Incompatible session type: ${session.runtimeType} (expecting ${WorkflowSession})',
        'session',
      );
    }
    // For workflow threads, messages are added directly via the internal AddMessages method
        // The MessageStore methods are used for agent invocation scenarios
        WorkflowSession.chatHistoryProvider.addMessages(session, messages);
    return WorkflowSession;
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    await this.validateWorkflowAsync();
    var WorkflowSession = await this.updateSessionAsync(
      messages,
      session,
      cancellationToken,
    ) ;
    var merger = new();
    for (final update in WorkflowSession.invokeStageAsync(cancellationToken)
                                                                     
                                                                     .withCancellation(cancellationToken)) {
      merger.addUpdate(update);
    }
    var response = merger.computeMerged(WorkflowSession.lastResponseId!, this.id, this.name);
    WorkflowSession.chatHistoryProvider.addMessages(WorkflowSession, response.messages);
    WorkflowSession.chatHistoryProvider.updateBookmark(WorkflowSession);
    return response;
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    await this.validateWorkflowAsync();
    var WorkflowSession = await this.updateSessionAsync(
      messages,
      session,
      cancellationToken,
    ) ;
    var merger = new();
    for (final update in WorkflowSession.invokeStageAsync(cancellationToken)
                                                                      
                                                                      .withCancellation(cancellationToken)) {
      merger.addUpdate(update);
      yield update;
    }
    var response = merger.computeMerged(WorkflowSession.lastResponseId!, this.id, this.name);
    WorkflowSession.chatHistoryProvider.addMessages(WorkflowSession, response.messages);
    WorkflowSession.chatHistoryProvider.updateBookmark(WorkflowSession);
  }
}
