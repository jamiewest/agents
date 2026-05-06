import 'dart:math';
import 'dart:collection';
import '../request_port.dart';
import 'package:extensions/system.dart';
import 'package:extensions/logging.dart';
import '../agent_response_event.dart';
import '../agent_response_update_event.dart';
import '../checkpointing/checkpoint.dart';
import '../execution/concurrent_event_sink.dart';
import '../execution/edge_map.dart';
import '../execution/external_request_sink.dart';
import '../execution/output_filter.dart';
import '../execution/runner_context.dart';
import '../execution/runner_state_data.dart';
import '../execution/state_manager.dart';
import '../execution/step_context.dart';
import '../execution/step_tracer.dart';
import '../execution/super_step_runner.dart';
import '../external_request.dart';
import '../external_request_context.dart';
import '../external_response.dart';
import '../observability/workflow_telemetry_context.dart';
import '../request_halt_event.dart';
import '../request_info_event.dart';
import '../run.dart';
import '../streaming_run.dart';
import '../workflow.dart';
import '../workflow_context.dart';
import '../workflow_event.dart';
import '../workflow_output_event.dart';
import '../../../map_extensions.dart';

class InProcessRunnerContext implements RunnerContext {
  InProcessRunnerContext(
    Workflow workflow,
    String sessionId,
    bool checkpointingEnabled,
    EventSink outgoingEvents,
    StepTracer? stepTracer,
    {Object? existingOwnershipSignoff = null, bool? subworkflow = null, bool? enableConcurrentRuns = null, Logger? logger = null, }
  ) :
      _workflow = workflow,
      _sessionId = sessionId,
      outgoingEvents = outgoingEvents {
    if (enableConcurrentRuns) {
      workflow.checkOwnership(existingOwnershipSignoff: existingOwnershipSignoff);
    } else {
      workflow.takeOwnership(this, existingOwnershipSignoff: existingOwnershipSignoff);
      this._previousOwnership = existingOwnershipSignoff;
      this._ownsWorkflow = true;
    }
    this._edgeMap = new(this, this._workflow, stepTracer);
    this._outputFilter = new(workflow);
    this.isCheckpointingEnabled = checkpointingEnabled;
    this.concurrentRunsEnabled = enableConcurrentRuns;
  }

  int _runEnded;

  final String _sessionId;

  final Workflow _workflow;

  late final Object? _previousOwnership;

  late bool _ownsWorkflow;

  late final EdgeMap _edgeMap;

  late final OutputFilter _outputFilter;

  late StepContext _nextStep;

  final Map<String, Future<Executor>> _executors;

  final Queue<Future Function()> _queuedExternalDeliveries;

  final Map<String, SuperStepRunner> _joinedSubworkflowRunners;

  final Map<String, ExternalRequest> _externalRequests;

  final EventSink outgoingEvents;

  final StateManager stateManager;

  late final bool isCheckpointingEnabled;

  late final bool concurrentRunsEnabled;

  WorkflowTelemetryContext get telemetryContext {
    return this._workflow.telemetryContext;
  }

  ExternalRequestSink registerPort(String executorId, RequestPort port, ) {
    if (!this._edgeMap.tryRegisterPort(this, executorId, port)) {
      throw StateError('A port with ID ${port.id} already exists.');
    }
    return this;
  }

  @override
  Future<Executor> ensureExecutor(
    String executorId,
    StepTracer? tracer,
    {CancellationToken? cancellationToken, }
  ) async {
    this.checkEnded();
    var executorTask = this._executors.getOrAdd(executorId, CreateExecutorAsync);
    /* TODO: unsupported node kind "unknown" */
    // async Task<Executor> CreateExecutorAsync(String id)
    //         {
      //             if (!this._workflow.ExecutorBindings.TryGetValue(executorId, registration))
      //             {
        //                 throw new InvalidOperationException($"Executor with ID '{executorId}' is not registered.");
        //             }
      //
      //             Executor executor = await registration.CreateInstanceAsync(this._sessionId);
      //             executor.AttachRequestContext(this.BindExternalRequestContext(executorId));
      //
      //             await executor.InitializeAsync(this.BindWorkflowContext(executorId), cancellationToken: cancellationToken)
      //                           ;
      //
      //             tracer?.TraceActivated(executorId);
      //
      //             if (executor is RequestInfoExecutor)
      //             {
        //                 requestInputExecutor.AttachRequestSink(this);
        //             }
      //
      //             if (executor is WorkflowHostExecutor)
      //             {
        //                 await workflowHostExecutor.AttachSuperStepContextAsync(this);
        //             }
      //
      //             return executor;
      //         }
    return await executorTask;
  }

  Future<Iterable<Type>> getStartingExecutorInputTypes({CancellationToken? cancellationToken}) async {
    var startingExecutor = await this.ensureExecutor(
      this._workflow.startExecutorId,
      tracer: null,
      cancellationToken,
    )
                                              ;
    return startingExecutor.inputTypes;
  }

  Future addExternalMessage(Object message, Type declaredType, ) {
    this.checkEnded();
    this._queuedExternalDeliveries.enqueue(PrepareExternalDeliveryAsync);
    return Future.value();
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask PrepareExternalDeliveryAsync()
    //         {
      //             DeliveryMapping? maybeMapping =
      //                 await this._edgeMap.PrepareDeliveryForInputAsync(new(message, ExecutorIdentity.None, declaredType))
      //                                    ;
      //
      //             maybeMapping?.MapInto(this._nextStep);
      //         }
  }

  Future addExternalResponse(ExternalResponse response) {
    this.checkEnded();
    this._queuedExternalDeliveries.enqueue(PrepareExternalDeliveryAsync);
    return Future.value();
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask PrepareExternalDeliveryAsync()
    //         {
      //             if (!this.CompleteRequest(response.RequestId))
      //             {
        //                 throw new InvalidOperationException($"No pending request with ID {response.RequestId} found in the workflow context.");
        //             }
      //
      //             DeliveryMapping? maybeMapping =
      //                 await this._edgeMap.PrepareDeliveryForResponseAsync(response)
      //                                    ;
      //
      //             maybeMapping?.MapInto(this._nextStep);
      //         }
  }

  bool get hasQueuedExternalDeliveries {
    return !this._queuedExternalDeliveries.isEmpty;
  }

  bool get joinedRunnersHaveActions {
    return this._joinedSubworkflowRunners.values.any((runner) => runner.hasUnprocessedMessages);
  }

  bool get nextStepHasActions {
    return this._nextStep.hasMessages ||
                                      this.hasQueuedExternalDeliveries ||
                                      this.joinedRunnersHaveActions;
  }

  bool get hasUnservicedRequests {
    return !this._externalRequests.isEmpty ||
                                         this._joinedSubworkflowRunners.values.any((runner) => runner.hasUnservicedRequests);
  }

  @override
  Future<StepContext> advance({CancellationToken? cancellationToken}) async {
    this.checkEnded();
    while (this._queuedExternalDeliveries.tryDequeue()) {
      // It's important we do not try to run these in parallel, because they may be modifying
            // inner edge state, etc.
            await deliveryPrep();
    }
    return (() { final _old = this._nextStep; this._nextStep = stepContext(; return _old; })());
  }

  @override
  Future addEvent(WorkflowEvent workflowEvent, {CancellationToken? cancellationToken, }) {
    this.checkEnded();
    return this.outgoingEvents.enqueueAsync(workflowEvent);
  }

  @override
  Future sendMessageAsync(
    String sourceId,
    Object message,
    {String? targetId, CancellationToken? cancellationToken, }
  ) async {
    var activity = this._workflow.telemetryContext.startMessageSendActivity(
      sourceId,
      targetId,
      message,
    );
    var traceContext = activity == null ? null : new Dictionary<String, String>();
    if (traceContext != null) {
      // Inject the current activity context into the carrier
            Propagators.defaultTextMapPropagator.inject(
                propagationContext(activity?.context ?? default, Baggage.current),
                traceContext,
                (carrier, key, value) => carrier[key] = value);
    }
    this.checkEnded();
    assert(this._executors.containsKey(sourceId));
    var source = await this.ensureExecutor(
      sourceId,
      tracer: null,
      cancellationToken,
    ) ;
    var declaredType = source.protocol.sendTypeTranslator.getDeclaredType(message.runtimeType);
    if (declaredType == null) {
      throw StateError('Executor ${sourceId} cannot send messages of type "${message.runtimeType.fullName}".');
    }
    var envelope = new(
      message,
      sourceId,
      declaredType,
      targetId: targetId,
      traceContext: traceContext,
    );
    Set<Edge>? edges;
    if (this._workflow.edges.containsKey(sourceId)) {
      for (final edge in edges) {
        var maybeMapping = await this._edgeMap.prepareDeliveryForEdgeAsync(
          edge,
          envelope,
          cancellationToken,
        )
                                       ;
        maybeMapping?.mapInto(this._nextStep);
      }
    }
  }

  Future yieldOutputAsync(
    String sourceId,
    Object output,
    {CancellationToken? cancellationToken, }
  ) async {
    this.checkEnded();
    if (output is AgentResponseUpdate) {
      final update = output as AgentResponseUpdate;
      await this.addEvent(
        agentResponseUpdateEvent(sourceId, update),
        cancellationToken,
      ) ;
      return;
    } else if (output is AgentResponse) {
      final response = output as AgentResponse;
      await this.addEvent(
        agentResponseEvent(sourceId, response),
        cancellationToken,
      ) ;
      return;
    }
    var sourceExecutor = await this.ensureExecutor(
      sourceId,
      tracer: null,
      cancellationToken,
    ) ;
    if (!sourceExecutor.canOutput(output.runtimeType)) {
      throw StateError('Cannot output Object of type ${output.runtimeType.toString()}. Expecting one of [${sourceExecutor.outputTypes.join(", ")}].');
    }
    if (this._outputFilter.canOutput(sourceId, output)) {
      await this.addEvent(
        workflowOutputEvent(output, sourceId),
        cancellationToken,
      ) ;
    }
  }

  ExternalRequestContext bindExternalRequestContext(String executorId) {
    this.checkEnded();
    return boundExternalRequestContext(this, executorId);
  }

  @override
  WorkflowContext bindWorkflowContext(String executorId, {Map<String, String>? traceContext, }) {
    this.checkEnded();
    return boundWorkflowContext(this, executorId, traceContext);
  }

  @override
  Future post(ExternalRequest request) {
    this.checkEnded();
    if (!this._externalRequests.tryAdd(request.requestId, request)) {
      throw ArgumentError("Pending request with id ${request.requestId} already exists.");
    }
    return this.addEvent(requestInfoEvent(request));
  }

  bool completeRequest(String requestId) {
    this.checkEnded();
    return this._externalRequests.tryRemoveKey(requestId);
  }

  (bool, String?) tryGetResponsePortExecutorId(String portId) {
    // TODO(transpiler): implement out-param body
    throw UnimplementedError();
  }

  Future prepareForCheckpoint({CancellationToken? cancellationToken}) {
    this.checkEnded();
    return Future.wait(this._executors.values.map(InvokeCheckpointingAsync));
    /* TODO: unsupported node kind "unknown" */
    // async Task InvokeCheckpointingAsync(Task<Executor> executorTask)
    //         {
      //             Executor executor = await executorTask;
      //             await executor.OnCheckpointingAsync(this.BindWorkflowContext(executor.Id), cancellationToken);
      //         }
  }

  Future notifyCheckpointLoaded({CancellationToken? cancellationToken}) {
    this.checkEnded();
    return Future.wait(this._executors.values.map(InvokeCheckpointRestoredAsync));
    /* TODO: unsupported node kind "unknown" */
    // async Task InvokeCheckpointRestoredAsync(Task<Executor> executorTask)
    //         {
      //             Executor executor = await executorTask;
      //             await executor.OnCheckpointRestoredAsync(this.BindWorkflowContext(executor.Id), cancellationToken);
      //         }
  }

  Future<RunnerStateData> exportState() {
    this.checkEnded();
    var queuedMessages = this._nextStep.exportMessages();
    var result = new(instantiatedExecutors: [...this._executors.keys],
                                     queuedMessages,
                                     outstandingRequests: [...this._externalRequests.values]);
    return new(result);
  }

  Future republishUnservicedRequests({CancellationToken? cancellationToken}) async {
    this.checkEnded();
    if (this.hasUnservicedRequests) {
      for (final requestId in this._externalRequests.keys) {
        await this.addEvent(
          requestInfoEvent(this._externalRequests[requestId]),
          cancellationToken,
        )
                          ;
      }
    }
  }

  Future importState(Checkpoint checkpoint) async {
    this.checkEnded();
    var importedState = checkpoint.runnerData;
    var executorTasks = importedState.instantiatedExecutors
                                                      .where((id) => !this._executors.containsKey(id))
                                                      .map((id) => this.ensureExecutor(id, tracer: null).future)
                                                      .toList();
    while (this._queuedExternalDeliveries.tryDequeue()) {}
    this._nextStep = stepContext();
    this._nextStep.importMessages(importedState.queuedMessages);
    this._externalRequests.clear();
    for (final request in importedState.outstandingRequests) {
      // TODO: Reduce the amount of data we need to store in the checkpoint by not storing the entire request Object.
            // For example, the Port Object is! needed - we should be able to reconstruct it from the ID and the workflow
            // definition.
            this._externalRequests[request.requestId] = request;
    }
    await Future.wait(executorTasks);
  }

  void checkEnded() {
    if (Volatile.read(_runEnded) == 1) {
      throw StateError("Workflow run for session ${this._sessionId} has been ended. Please start a new Run or StreamingRun.");
    }
  }

  Future endRun() async {
    if ((() { final _old = this._runEnded; this._runEnded = 1; return _old; })() == 0) {
      for (final executorId in this._executors.keys) {
        var executorTask = this._executors[executorId];
        var executor = await executorTask;
        if (executor is AsyncDisposable) {
          final asyncDisposable = executor as AsyncDisposable;
          await asyncDisposable.disposeAsync();
        } else if (executor is Disposable) {
          final disposable = executor as Disposable;
          disposable.dispose();
        }
      }
      if (this._ownsWorkflow) {
        await this._workflow.releaseOwnershipAsync(
          this,
          this._previousOwnership,
        ) ;
        this._ownsWorkflow = false;
      }
    }
  }

  Iterable<SuperStepRunner> get joinedSubworkflowRunners {
    return this._joinedSubworkflowRunners.values;
  }

  @override
  Future<String> attachSuperstep(
    SuperStepRunner superStepRunner,
    {CancellationToken? cancellationToken, }
  ) {
    // This needs to be a thread-safe ordered collection because we can potentially instantiate executors
        // in parallel, which means multiple sub-workflows could be attaching at the same time.
        String joinId;
    do {
      joinId = List.generate(32, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
    } while (!this._joinedSubworkflowRunners.tryAdd(joinId, superStepRunner));
    return Future.value();
  }

  @override
  Future<bool> detachSuperstep(String joinId) {
    return new(this._joinedSubworkflowRunners.tryRemoveKey(joinId));
  }

  Future forwardWorkflowEvent(WorkflowEvent workflowEvent, CancellationToken cancellationToken, ) {
    return this.addEvent(workflowEvent, cancellationToken);
  }

  Future sendMessageAsync(
    String senderId,
    TMessage message,
    CancellationToken cancellationToken,
  ) {
    return this.sendMessage(
      senderId,
      message,
      cancellationToken: cancellationToken,
    );
  }

  Future yieldOutputAsync(String senderId, TOutput output, CancellationToken cancellationToken, ) {
    return this.yieldOutput(senderId, output, cancellationToken);
  }
}
class BoundExternalRequestContext implements ExternalRequestContext {
  const BoundExternalRequestContext(InProcessRunnerContext RunnerContext, String ExecutorId, );

  @override
  ExternalRequestSink registerPort(RequestPort port) {
    return RunnerContext.registerPort(ExecutorId, port);
  }
}
class BoundWorkflowContext implements WorkflowContext {
  const BoundWorkflowContext(
    InProcessRunnerContext RunnerContext,
    String ExecutorId,
    Map<String, String>? traceContext,
  ) : traceContext = traceContext;

  @override
  Future addEvent(WorkflowEvent workflowEvent, {CancellationToken? cancellationToken, }) {
    return RunnerContext.addEvent(workflowEvent, cancellationToken);
  }

  @override
  Future sendMessage(Object message, {String? targetId, CancellationToken? cancellationToken, }) {
    return RunnerContext.sendMessage(
      ExecutorId,
      message,
      targetId,
      cancellationToken,
    );
  }

  @override
  Future yieldOutput(Object output, {CancellationToken? cancellationToken, }) {
    return RunnerContext.yieldOutput(ExecutorId, output, cancellationToken);
  }

  @override
  Future requestHalt() {
    return this.addEvent(requestHaltEvent());
  }

  @override
  Future<T?> readState<T>(String key, {String? scopeName, CancellationToken? cancellationToken, }) {
    return RunnerContext.stateManager.readStateAsync<T>(ExecutorId, scopeName, key);
  }

  @override
  Future<T> readOrInitState<T>(
    String key,
    T Function() initialStateFactory,
    {String? scopeName, CancellationToken? cancellationToken, }
  ) {
    return RunnerContext.stateManager.readOrInitStateAsync(
      ExecutorId,
      scopeName,
      key,
      initialStateFactory,
    );
  }

  @override
  Future<Set<String>> readStateKeys({String? scopeName, CancellationToken? cancellationToken, }) {
    return RunnerContext.stateManager.readKeysAsync(ExecutorId, scopeName);
  }

  @override
  Future queueStateUpdate<T>(
    String key,
    T? value,
    {String? scopeName, CancellationToken? cancellationToken, }
  ) {
    return RunnerContext.stateManager.writeStateAsync(ExecutorId, scopeName, key, value);
  }

  @override
  Future queueClearScope({String? scopeName, CancellationToken? cancellationToken, }) {
    return RunnerContext.stateManager.clearStateAsync(ExecutorId, scopeName);
  }

  Map<String, String>? get traceContext {
    return traceContext;
  }

  bool get concurrentRunsEnabled {
    return RunnerContext.concurrentRunsEnabled;
  }
}
