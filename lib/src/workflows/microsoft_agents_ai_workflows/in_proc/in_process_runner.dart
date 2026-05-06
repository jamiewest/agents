import 'dart:math';
import 'dart:collection';
import 'package:extensions/system.dart';
import '../checkpoint_info.dart';
import '../checkpointing/checkpoint.dart';
import '../checkpointing/checkpoint_manager.dart';
import '../checkpointing/checkpointing_handle.dart';
import '../checkpointing/type_id.dart';
import '../checkpointing/workflow_info.dart';
import '../execution/async_run_handle.dart';
import '../execution/concurrent_event_sink.dart';
import '../execution/edge_map.dart';
import '../execution/execution_mode.dart';
import '../execution/message_envelope.dart';
import '../execution/step_context.dart';
import '../execution/super_step_runner.dart';
import '../external_response.dart';
import '../observability/workflow_telemetry_context.dart';
import '../checkpointing/workflow_representation_extensions.dart';
import '../workflow.dart';
import '../workflow_error_event.dart';
import '../workflow_event.dart';
import 'in_proc_step_tracer.dart';
import 'in_process_runner_context.dart';
import '../../../map_extensions.dart';

/// Provides a local, in-process runner for executing a workflow using the
/// specified input type.
///
/// Remarks: [InProcessRunner] enables step-by-step execution of a workflow
/// graph entirely within the current process, without distributed
/// coordination. It is primarily intended for testing, debugging, or
/// scenarios where workflow execution does not require executor distribution.
class InProcessRunner implements CheckpointingHandle,SuperStepRunner {
  InProcessRunner(
    Workflow workflow,
    CheckpointManager? checkpointManager,
    {String? sessionId = null, Object? existingOwnerSignoff = null, bool? subworkflow = null, bool? enableConcurrentRuns = null, Iterable<Type>? knownValidInputTypes = null, }
  ) :
      workflow = workflow,
      checkpointManager = checkpointManager {
    if (enableConcurrentRuns && !workflow.allowConcurrent) {
      throw StateError(
        'workflow must only consist of cross-run share-capable or factory-created executors. Executors '
        'not supporting concurrent: ${workflow.nonConcurrentExecutorIds.join(", ")}');
    }
    this.sessionId = sessionId ?? List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    this.startExecutorId = workflow.startExecutorId;
    this.runContext = inProcessRunnerContext(
      workflow,
      this.sessionId,
      checkpointingEnabled: checkpointManager != null,
      this.outgoingEvents,
      this.stepTracer,
      existingOwnerSignoff,
      subworkflow,
      enableConcurrentRuns,
    );
    this._knownValidInputTypes = knownValidInputTypes != null
                                   ? [...knownValidInputTypes]
                                   : [];
    // Initialize the runners for each of the edges, along with the state for edges that need it.
        this.edgeMap = edgeMap(
          this.runContext,
          this.workflow.edges,
          this.workflow.ports.values,
          this.workflow.startExecutorId,
          this.stepTracer,
        );
  }

  late final String sessionId;

  late final String startExecutorId;

  /// Gating flag for deferred event republishing after checkpoint restore.
  ///
  /// Remarks: Written with [Int32)] in [CancellationToken)] and consumed
  /// atomically with [Int32)] in [CancellationToken)]. The write does not need
  /// a full memory barrier because it is sequenced before the [AsyncRunHandle]
  /// constructor by the `await` in [CancellationToken)]. The constructor is the
  /// only code path that triggers consumption (via the event stream's subscribe
  /// and republish flow). Note: [AsyncRunHandle] also reads
  /// [HasUnservicedRequests] in its constructor to signal the run loop, but
  /// that property reads from [InProcessRunnerContext]'s request dictionary
  /// (restored during [CancellationToken)]), not from this flag. The two are
  /// independent: `HasUnservicedRequests` triggers the run loop;
  /// `_needsRepublish` triggers event emission.
  int _needsRepublish;

  late final Set<Type> _knownValidInputTypes;

  final InProcStepTracer stepTracer;

  Workflow workflow;

  late InProcessRunnerContext runContext;

  final CheckpointManager? checkpointManager;

  late EdgeMap edgeMap;

  final ConcurrentEventSink outgoingEvents;

  WorkflowInfo? _workflowInfoCache;

  late CheckpointInfo? _lastCheckpointInfo;

  final List<CheckpointInfo> _checkpoints = [];

  static InProcessRunner createTopLevelRunner(
    Workflow workflow,
    CheckpointManager? checkpointManager,
    {String? sessionId, bool? enableConcurrentRuns, Iterable<Type>? knownValidInputTypes, }
  ) {
    return inProcessRunner(workflow,
                                   checkpointManager,
                                   sessionId,
                                   enableConcurrentRuns: enableConcurrentRuns,
                                   knownValidInputTypes: knownValidInputTypes);
  }

  static InProcessRunner createSubworkflowRunner(
    Workflow workflow,
    CheckpointManager? checkpointManager,
    {String? sessionId, Object? existingOwnerSignoff, bool? enableConcurrentRuns, Iterable<Type>? knownValidInputTypes, }
  ) {
    return inProcessRunner(workflow,
                                   checkpointManager,
                                   sessionId,
                                   existingOwnerSignoff: existingOwnerSignoff,
                                   enableConcurrentRuns: enableConcurrentRuns,
                                   knownValidInputTypes: knownValidInputTypes,
                                   subworkflow: true);
  }

  WorkflowTelemetryContext get telemetryContext {
    return this.workflow.telemetryContext;
  }

  @override
  Future<bool> isValidInputType({Type? messageType, CancellationToken? cancellationToken, }) async {
    if (this._knownValidInputTypes.contains(messageType)) {
      return true;
    }
    var startingExecutor = await this.runContext.ensureExecutor(
      this.workflow.startExecutorId,
      tracer: null,
      cancellationToken,
    ) ;
    if (startingExecutor.canHandle(messageType)) {
      this._knownValidInputTypes.add(messageType);
      return true;
    }
    return false;
  }

  @override
  Future<bool> enqueueMessageUntyped(
    Object message,
    {Type? declaredType, CancellationToken? cancellationToken, }
  ) async {
    this.runContext.checkEnded();
    if (message is ExternalResponse) {
      final response = message as ExternalResponse;
      await this.runContext.addExternalResponseAsync(response);
    }
    if (!await this.isValidInputTypeAsync(declaredType, cancellationToken)) {
      return false;
    }
    await this.runContext.addExternalMessageAsync(message, declaredType);
    return true;
  }

  @override
  Future<bool> enqueueMessage<T>(T message, {CancellationToken? cancellationToken, }) {
    return this.enqueueMessageUntypedAsync(message, T, cancellationToken);
  }

  Future enqueueResponse(ExternalResponse response, CancellationToken cancellationToken, ) {
    return this.runContext.addExternalResponseAsync(response);
  }

  Future raiseWorkflowEvent(WorkflowEvent workflowEvent) {
    return this.outgoingEvents.enqueueAsync(workflowEvent);
  }

  Future<AsyncRunHandle> beginStream(ExecutionMode mode, {CancellationToken? cancellationToken, }) {
    this.runContext.checkEnded();
    return new(asyncRunHandle(this, this, mode));
  }

  Future<AsyncRunHandle> resumeStream(
    ExecutionMode mode,
    CheckpointInfo fromCheckpoint,
    {bool? republishPendingEvents, CancellationToken? cancellationToken, }
  ) async {
    this.runContext.checkEnded();
    if (this.checkpointManager == null) {
      throw StateError(
        'This runner was not configured with a checkpointManager, '
        'so it cannot restore checkpoints.',
      );
    }
    // Restore checkpoint state without republishing pending request events.
        // The event stream will republish them after subscribing so that events
        // are never lost to an absent subscriber.
        await this.restoreCheckpointCoreAsync(
          fromCheckpoint,
          cancellationToken,
        ) ;
    if (republishPendingEvents) {
      // Signal the event stream to republish pending requests after subscribing.
            // This is consumed atomically by RepublishPendingEventsAsync.
            Volatile.write(_needsRepublish, 1);
    }
    return asyncRunHandle(this, this, mode);
  }

  bool get hasUnservicedRequests {
    return this.runContext.hasUnservicedRequests;
  }

  bool get hasUnprocessedMessages {
    return this.runContext.nextStepHasActions;
  }

  (bool, String?) tryGetResponsePortExecutorId(String portId) {
    // TODO(transpiler): implement out-param body
    throw UnimplementedError();
  }

  Future republishPendingEvents(CancellationToken cancellationToken) {
    if ((() { final _old = this._needsRepublish; this._needsRepublish = 0; return _old; })() != 0) {
      return this.runContext.republishUnservicedRequestsAsync(cancellationToken);
    }
    return Future.value();
  }

  bool get isCheckpointingEnabled {
    return this.runContext.isCheckpointingEnabled;
  }

  List<CheckpointInfo> get checkpoints {
    return this._checkpoints;
  }

  Future<bool> runSuperStep(CancellationToken cancellationToken) async {
    this.runContext.checkEnded();
    if (cancellationToken.isCancellationRequested) {
      return false;
    }
    var currentStep = await this.runContext.advanceAsync(cancellationToken);
    if (currentStep.hasMessages ||
            this.runContext.hasQueuedExternalDeliveries ||
            this.runContext.joinedRunnersHaveActions) {
      try {
        await this.runSuperstepAsync(currentStep, cancellationToken);
      } catch (e, s) {
        if (e is OperationCanceledException) {
          final  = e as OperationCanceledException;
          {}
        } else     if (e is Exception) {
          final e = e as Exception;
          {
            await this.raiseWorkflowEventAsync(workflowErrorEvent(e));
          }
        } else {
          rethrow;
        }
      }
      return true;
    }
    return false;
  }

  Future deliverMessages(
    String receiverId,
    Queue<MessageEnvelope> envelopes,
    CancellationToken cancellationToken,
  ) async {
    var executor = await this.runContext.ensureExecutor(
      receiverId,
      this.stepTracer,
      cancellationToken,
    ) ;
    this.stepTracer.traceActivated(receiverId);
    var tracelessContext = this.runContext.bindWorkflowContext(receiverId);
    try {
      await executor.onMessageDeliveryStartingAsync(tracelessContext, cancellationToken)
                          ;
      while (envelopes.tryDequeue()) {
        (
          Object message,
          TypeId messageType,
        ) = await translateMessageAsync(envelope);
        await executor.executeCoreAsync(
                    message,
                    messageType,
                    this.runContext.bindWorkflowContext(receiverId, envelope.traceContext),
                    this.telemetryContext,
                    cancellationToken
                );
      }
    } finally {
      await executor.onMessageDeliveryFinishedAsync(tracelessContext, cancellationToken)
                          ;
    }
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<(Object, TypeId)> TranslateMessageAsync(MessageEnvelope envelope)
    //         {
      //             Object? value = envelope.Message;
      //             TypeId messageType = envelope.MessageType;
      //
      //             if (!envelope.IsExternal)
      //             {
        //                 Executor source = await this.RunContext.EnsureExecutorAsync(envelope.SourceId, this.StepTracer, cancellationToken);
        //                 Type? actualType = source.Protocol.SendTypeTranslator.MapTypeId(envelope.MessageType);
        //                 if (actualType == null)
        //                 {
          //                     // In principle, this should never happen, since we always use the SendTypeTranslator to generate the outgoing TypeId in the first place.
          //                     throw new InvalidOperationException($"Cannot translate message type ID '{envelope.MessageType}' from executor '{source.Id}'.");
          //                 }
        //
        //                 messageType = new(actualType);
        //
        //                 if (value is PortableValue PortableValue &&
        //                     !PortableValue.IsType(actualType, value))
        //                 {
          //                     throw new InvalidOperationException($"Cannot interpret incoming message of type '{PortableValue.TypeId}' as type '{actualType.FullName}'.");
          //                 }
        //             }
      //
      //             return (value, messageType);
      //         }
  }

  Future runSuperstep(StepContext currentStep, CancellationToken cancellationToken, ) async {
    await this.raiseWorkflowEventAsync(this.stepTracer.advance(currentStep));
    var receiverTasks = currentStep.queuedMessages.keys
                       .map((receiverId) => this.deliverMessagesAsync(receiverId, currentStep.messagesFor(receiverId), cancellationToken).future)
                       .toList();
    // TODO: Should we let the user specify that they want strictly turn-based execution of the edges, vs. concurrent?
        // (Simply substitute a strategy that replaces Future.wait with a loop with an await in the middle. Difficulty is
        // that we would need to avoid firing the tasks when we call InvokeEdgeAsync, or RouteExternalMessageAsync.
        await Future.wait(receiverTasks);
    var subworkflowTasks = [];
    for (final subworkflowRunner in this.runContext.joinedSubworkflowRunners) {
      subworkflowTasks.add(subworkflowRunner.runSuperStepAsync(cancellationToken).future);
    }
    await Future.wait(subworkflowTasks);
    await this.checkpointAsync(cancellationToken);
    await this.raiseWorkflowEventAsync(this.stepTracer.complete(this.runContext.nextStepHasActions, this.runContext.hasUnservicedRequests))
                  ;
  }

  Future checkpoint({CancellationToken? cancellationToken}) async {
    this.runContext.checkEnded();
    if (this.checkpointManager == null) {
      // Always publish the state updates, even in the absence of a checkpointManager.
            await this.runContext.stateManager.publishUpdatesAsync(this.stepTracer);
      return;
    }
    var prepareTask = this.runContext.prepareForCheckpointAsync(cancellationToken);
    // Create a representation of the current workflow if it does not already exist.
        this._workflowInfoCache ??= this.workflow.toWorkflowInfo();
    var edgeData = await this.edgeMap.exportStateAsync();
    await prepareTask;
    await this.runContext.stateManager.publishUpdatesAsync(this.stepTracer);
    var runnerData = await this.runContext.exportStateAsync();
    var stateData = await this.runContext.stateManager.exportStateAsync();
    var checkpoint = new(
      this.stepTracer.stepNumber,
      this._workflowInfoCache,
      runnerData,
      stateData,
      edgeData,
      this._lastCheckpointInfo,
    );
    this._lastCheckpointInfo = await this.checkpointManager.commitCheckpointAsync(
      this.sessionId,
      checkpoint,
    ) ;
    this.stepTracer.traceCheckpointCreated(this._lastCheckpointInfo);
    this._checkpoints.add(this._lastCheckpointInfo);
  }

  /// Restores checkpoint state and re-emits any pending external request
  /// events.
  ///
  /// Remarks: This is the [CheckpointingHandle] implementation used for runtime
  /// restores where the event stream subscription is already active. For
  /// initial resumes, [CancellationToken)] calls [CancellationToken)] directly
  /// and defers republishing to the event stream.
  @override
  Future restoreCheckpoint(
    CheckpointInfo checkpointInfo,
    {CancellationToken? cancellationToken, }
  ) async {
    await this.restoreCheckpointCoreAsync(checkpointInfo, cancellationToken);
    // Republish pending request events. This is safe for runtime restores where
        // the event stream is already subscribed. For initial resumes the event stream
        // handles republishing itself, so ResumeStreamAsync calls RestoreCheckpointCoreAsync directly.
        await this.runContext.republishUnservicedRequestsAsync(cancellationToken);
  }

  /// Restores checkpoint state (queued messages, executor state, edge state,
  /// etc.) without republishing pending request events. The caller is
  /// responsible for ensuring events are republished after an event subscriber
  /// is attached.
  Future restoreCheckpointCore(
    CheckpointInfo checkpointInfo,
    {CancellationToken? cancellationToken, }
  ) async {
    this.runContext.checkEnded();
    if (this.checkpointManager == null) {
      throw StateError(
        'This run was not configured with a checkpointManager, '
        'so it cannot restore checkpoints.',
      );
    }
    var checkpoint = await this.checkpointManager.lookupCheckpointAsync(
      this.sessionId,
      checkpointInfo,
    )
                                                            ;
    if (!this.checkWorkflowMatch(checkpoint)) {
      throw invalidDataException("The specified checkpoint is! compatible with the workflow associated with this runner.");
    }
    var restoreCheckpointIndexTask = updateCheckpointIndexAsync();
    await this.runContext.stateManager.importStateAsync(checkpoint);
    await this.runContext.importStateAsync(checkpoint);
    var executorNotifyTask = this.runContext.notifyCheckpointLoadedAsync(cancellationToken);
    await this.edgeMap.importStateAsync(checkpoint);
    await Future.wait(executorNotifyTask,
                           restoreCheckpointIndexTask.future);
    this._lastCheckpointInfo = checkpointInfo;
    this.stepTracer.reload(this.stepTracer.stepNumber);
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask UpdateCheckpointIndexAsync()
    //         {
      //             this._checkpoints.Clear();
      //             this._checkpoints.AddRange(await this.CheckpointManager!.RetrieveIndexAsync(this.SessionId));
      //         }
  }

  bool checkWorkflowMatch(Checkpoint checkpoint) {
    return checkpoint.workflow.isMatch(this.workflow);
  }

  @override
  Future requestEndRun() {
    return this.runContext.endRunAsync();
  }
}
