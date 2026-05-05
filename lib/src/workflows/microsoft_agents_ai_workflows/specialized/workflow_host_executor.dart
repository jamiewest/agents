import 'package:extensions/system.dart';
import '../checkpoint_info.dart';
import '../checkpointing/in_memory_checkpoint_manager.dart';
import '../checkpointing/request_port_info.dart';
import '../execution/async_run_handle.dart';
import '../execution/execution_mode.dart';
import '../execution/super_step_join_context.dart';
import '../executor_options.dart';
import '../external_request.dart';
import '../external_response.dart';
import '../in_proc/in_process_runner.dart';
import '../portable_value.dart';
import '../protocol_builder.dart';
import '../protocol_descriptor.dart';
import '../request_halt_event.dart';
import '../request_info_event.dart';
import '../streaming_run.dart';
import '../subworkflow_error_event.dart';
import '../subworkflow_warning_event.dart';
import '../super_step_completed_event.dart';
import '../super_step_started_event.dart';
import '../workflow.dart';
import '../workflow_context.dart';
import '../workflow_error_event.dart';
import '../workflow_event.dart';
import '../workflow_output_event.dart';
import '../workflow_started_event.dart';
import '../workflow_warning_event.dart';
import '../../../map_extensions.dart';

class WorkflowHostExecutor extends Executor implements AsyncDisposable {
  WorkflowHostExecutor(
    String id,
    Workflow workflow,
    ProtocolDescriptor workflowProtocol,
    String sessionId,
    Object ownershipToken,
    {ExecutorOptions? options = null, },
  ) :
      _workflow = workflow,
      _workflowProtocol = workflowProtocol,
      _sessionId = sessionId,
      _ownershipToken = ownershipToken {
    this._options = options ?? new();
  }

  final String _sessionId;

  final Workflow _workflow;

  final ProtocolDescriptor _workflowProtocol;

  final Object _ownershipToken;

  late InProcessRunner? _activeRunner;

  late InMemoryCheckpointManager? _checkpointManager;

  late final ExecutorOptions _options;

  final Map<String, RequestPortInfo> _pendingResponsePorts = new();

  late SuperStepJoinContext? _joinContext;

  late String? _joinId;

  late StreamingRun? _run;

  bool get withCheckpointing {
    return this._checkpointManager != null;
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    if (this._options.autoYieldOutputHandlerResultObject) {
      protocolBuilder = protocolBuilder.yieldsOutputTypes(this._workflowProtocol.yields);
    }
    return protocolBuilder.configureRoutes((routeBuilder) => routeBuilder.addCatchAll(this.queueExternalMessageAsync))
                              .sendsMessageTypes(this._workflowProtocol.yields);
  }

  Future queueExternalMessage(
    PortableValue PortableValue,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async  {
    if (PortableValue.isValue(response)) {
      response = this.checkAndUnqualifyResponse(response);
      await this.ensureRunSendMessageAsync(
        response,
        cancellationToken: cancellationToken,
      ) ;
    } else {
      var runner = await this.ensureRunnerAsync();
      var validInputTypes = await runner.runContext.getStartingExecutorInputTypesAsync(cancellationToken);
      for (final candidateType in validInputTypes) {
        Object? message;
        if (PortableValue.isType(candidateType)) {
          await this.ensureRunSendMessageAsync(
            message,
            candidateType,
            cancellationToken: cancellationToken,
          ) ;
          return;
        }
      }
    }
  }

  SuperStepJoinContext get joinContext {
    if (this._joinContext == null) {
      throw StateError("Must attach to a join context before starting the run.");
    }
    return this._joinContext!;
  }

  Future<InProcessRunner> ensureRunner() async  {
    if (this._activeRunner == null) {
      if (this.joinContext.isCheckpointingEnabled) {
        // Use a seprate in-memory checkpoint manager for scoping purposes. We do not need to worry about
                // serialization because we will be relying on the parent workflow's checkpoint manager to do that,
                // if needed. For our purposes, all we need is to keep a faithful representation of the checkpointed
                // objects so we can emit them back to the parent workflow on checkpoint creation.
                this._checkpointManager ??= inMemoryCheckpointManager();
      }
      this._activeRunner = InProcessRunner.createSubworkflowRunner(this._workflow,
                                                                         this._checkpointManager,
                                                                         this._sessionId,
                                                                         this._ownershipToken,
                                                                         this.joinContext.concurrentRunsEnabled);
    }
    return this._activeRunner;
  }

  Future<StreamingRun> ensureRunSendMessage({Object? incomingMessage, Type? incomingMessageType, bool? resume, CancellationToken? cancellationToken, }) async  {
    assert(
      this._joinContext != null,
      "Must attach to a join context before starting the run.",
    );
    if (this._run != null) {
      if (incomingMessage != null) {
        await this._run.trySendMessageUntypedAsync(
          incomingMessage,
          incomingMessageType ?? incomingMessage.runtimeType,
        ) ;
      }
      return this._run;
    }
    var activeRunner = await this.ensureRunnerAsync();
    AsyncRunHandle runHandle;
    if (this.withCheckpointing) {
      if (resume) {
        CheckpointInfo lastCheckpoint;
        if (!this._checkpointManager.tryGetLastCheckpoint(this._sessionId)) {
          throw StateError("No checkpoints available to resume from.");
        }
        runHandle = await activeRunner.resumeStreamAsync(
          ExecutionMode.subworkflow,
          lastCheckpoint!,
          cancellationToken,
        )
                                              ;
        if (incomingMessage != null) {
          await runHandle.enqueueMessageUntypedAsync(
            incomingMessage,
            cancellationToken: cancellationToken,
          ) ;
        }
      } else if (incomingMessage != null) {
        runHandle = await activeRunner.beginStreamAsync(
          ExecutionMode.subworkflow,
          cancellationToken,
        )
                                              ;
        await runHandle.enqueueMessageUntypedAsync(
          incomingMessage,
          cancellationToken: cancellationToken,
        ) ;
      } else {
        throw StateError("Cannot start a checkpointed workflow run without an incoming message or resume flag.");
      }
    } else {
      runHandle = await activeRunner.beginStreamAsync(
        ExecutionMode.subworkflow,
        cancellationToken,
      ) ;
      await runHandle.enqueueMessageUntypedAsync(
        incomingMessage,
        cancellationToken: cancellationToken,
      ) ;
    }
    this._run = new(runHandle);
    this._joinId = await this._joinContext.attachSuperstepAsync(
      activeRunner,
      cancellationToken,
    ) ;
    activeRunner.outgoingEvents.eventRaised += this.forwardWorkflowEventAsync;
    return this._run;
  }

  ExternalResponse? checkAndUnqualifyResponse(ExternalResponse response) {
    RequestPortInfo originalPort;
    if (this._pendingResponsePorts.tryRemoveKey(response.requestId)) {
      return response with { PortInfo = originalPort };
    }
    if (!response.portInfo.portId.startsWith('${this.id}.')) {
      return null;
    }
    var unqualifiedPort = response.portInfo with { PortId = response.portInfo.portId.substring(this.id.length + 1) };
    return response with { PortInfo = unqualifiedPort };
  }

  ExternalRequest qualifyRequestPortId(ExternalRequest internalRequest) {
    var requestPort = internalRequest.portInfo with { PortId = '${this.id}.${internalRequest.portInfo.portId}' };
    return internalRequest with { PortInfo = requestPort };
  }

  Future forwardWorkflowEvent(Object? sender, WorkflowEvent evt, ) async  {
    try {
      var resultTask = Task.value(null);
      switch (evt) {
        case WorkflowStartedEvent || SuperStepStartedEvent || SuperStepCompletedEvent:
        case RequestInfoEvent requestInfoEvt:
        var request = requestInfoEvt.request;
        this._pendingResponsePorts[request.requestId] = request.portInfo;
        resultTask = this._joinContext?.sendMessage(
          this.id,
          this.qualifyRequestPortId(request),
        ) .future ?? Task.value(null);
        case WorkflowErrorEvent errorEvent:
        resultTask = this._joinContext?.forwardWorkflowEventAsync(subworkflowErrorEvent(this.id, errorEvent.data as Exception)).future ?? Task.value(null);
        case WorkflowOutputEvent outputEvent:
        if (this._joinContext != null &&
                        this._options.autoSendMessageHandlerResultObject
                        && outputEvent.data != null) {
          resultTask = this._joinContext.sendMessage(this.id, outputEvent.data).future;
        }
        if (this._joinContext != null &&
                        this._options.autoYieldOutputHandlerResultObject
                        && outputEvent.data != null) {
          resultTask = this._joinContext.yieldOutput(this.id, outputEvent.data).future;
        }
        case RequestHaltEvent requestHaltEvent:
        resultTask = this._joinContext?.forwardWorkflowEventAsync(requestHaltEvent()).future ?? Task.value(null);
        case WorkflowWarningEvent warningEvent:
        if (warningEvent.data is String) {
          final warningMessage = warningEvent.data as String;
          resultTask = this._joinContext?.forwardWorkflowEventAsync(subworkflowWarningEvent(this.id, warningMessage)).future ?? Task.value(null);
        }
        default:
        resultTask = this._joinContext?.forwardWorkflowEventAsync(evt).future ?? Task.value(null);
      }
      await resultTask;
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          try {
            _ = this._joinContext?.forwardWorkflowEventAsync(subworkflowErrorEvent(this.id, ex)).future;
          } catch (e, s) {
            {}
          }
        }
      } else {
        rethrow;
      }
    }
  }

  Future attachSuperStepContext(SuperStepJoinContext joinContext) async  {
    this._joinContext = joinContext;
  }

  @override
  Future onCheckpointing(WorkflowContext context, {CancellationToken? cancellationToken, }) async  {
    await context.queueStateUpdate(
      CheckpointManagerStateKey,
      this._checkpointManager,
      cancellationToken: cancellationToken,
    ) ;
    await context.queueStateUpdate(PendingResponsePortsStateKey,
                                            new Dictionary<String, RequestPortInfo>(
                                              this._pendingResponsePorts,
                                              ,
                                            ),
                                            cancellationToken: cancellationToken);
    await super.onCheckpointingAsync(context, cancellationToken);
  }

  @override
  Future onCheckpointRestored(
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    await super.onCheckpointRestoredAsync(context, cancellationToken);
    var manager = await context.readStateAsync<InMemoryCheckpointManager>(
      CheckpointManagerStateKey,
      cancellationToken: cancellationToken,
    )  ?? new();
    if (this._checkpointManager == manager) {} else {
      this._checkpointManager = manager;
      await this.resetAsync();
    }
    this._pendingResponsePorts.clear();
    var pendingResponsePorts = await context.readStateAsync<Dictionary<String, RequestPortInfo>>(
      PendingResponsePortsStateKey,
      cancellationToken: cancellationToken,
    )
                          ?? [];
    for (final pendingResponsePort in pendingResponsePorts) {
      this._pendingResponsePorts[pendingResponsePort.key] = pendingResponsePort.value;
    }
    await this.ensureRunSendMessageAsync(
      resume: true,
      cancellationToken: cancellationToken,
    ) ;
  }

  Future reset() async  {
    if (this._run != null) {
      await this._run.disposeAsync();
      this._run = null;
    }
    this._pendingResponsePorts.clear();
    if (this._activeRunner != null) {
      this._activeRunner.outgoingEvents.eventRaised -= this.forwardWorkflowEventAsync;
      await this._activeRunner.requestEndRunAsync();
      this._activeRunner = null;
    }
    if (this._joinContext != null && this._joinId != null) {
      await this._joinContext.detachSuperstepAsync(this._joinId);
      this._joinId = null;
    }
  }

  @override
  Future dispose() {
    return this.resetAsync();
  }
}
