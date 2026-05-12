import 'dart:async';

import 'package:clock/clock.dart';
import 'package:extensions/system.dart';

import '../execution/concurrent_event_sink.dart';
import '../execution/edge_map.dart';
import '../execution/message_envelope.dart';
import '../execution/output_filter.dart';
import '../execution/runner_state_data.dart';
import '../execution/state_manager.dart';
import '../execution/step_tracer.dart';
import '../execution/super_step_join_context.dart';
import '../executor.dart';
import '../executor_binding.dart';
import '../external_request.dart';
import '../external_response.dart';
import '../message_router.dart';
import '../request_info_event.dart';
import '../request_port.dart';
import '../workflow.dart';
import '../workflow_context.dart';
import '../workflow_event.dart';
import '../workflow_output_event.dart';
import 'in_proc_step_tracer.dart';

/// Workflow context extended with state read/write support and sub-workflow
/// attachment for in-process execution.
abstract interface class WorkflowStateContext implements WorkflowContext {
  /// Reads the value for [key] as [T] in this executor's scope.
  T? readState<T>(String key, {String? scopeName});

  /// Reads [key] as [T], initialising with [factory] if absent.
  T readOrInitState<T>(
    String key,
    T Function() factory, {
    String? scopeName,
  });

  /// Returns the set of keys stored in this executor's scope.
  Set<String> readStateKeys({String? scopeName});

  /// Queues an upsert of [value] under [key].
  void queueStateUpdate<T>(String key, T? value, {String? scopeName});

  /// Queues deletion of all keys in this executor's scope.
  void queueClearScope({String? scopeName});

  /// Emits [event] to the workflow output stream.
  Future<void> addEventAsync(
    WorkflowEvent event, {
    CancellationToken? cancellationToken,
  });

  /// Requests that the workflow halt after the current superstep completes.
  Future<void> requestHaltAsync({CancellationToken? cancellationToken});

  /// Mutable trace metadata for the current step.
  Map<String, Object?> get traceContext;

  /// Whether this workflow run supports concurrent execution.
  bool get concurrentRunsEnabled;

  /// Gets the superstep join context used to attach sub-workflow runners.
  SuperStepJoinContext get superstepJoinContext;
}

/// Orchestrates in-process workflow execution: instantiates executors, routes
/// messages through edges, manages state, and participates in superstep joins.
final class InProcessRunnerContext implements SuperStepJoinContext {
  /// Creates an [InProcessRunnerContext].
  InProcessRunnerContext({
    required Workflow workflow,
    required String sessionId,
    required bool checkpointingEnabled,
    required IEventSink outgoingEvents,
    required InProcStepTracer stepTracer,
    bool enableConcurrentRuns = false,
  }) : _workflow = workflow,
       _sessionId = sessionId,
       _outgoingEvents = outgoingEvents,
       _stepTracer = stepTracer,
       _outputFilter = OutputFilter(workflow),
       _edgeRouter = MessageRouter(
         EdgeMap(workflow.reflectEdges()),
         RunnerStateData(),
       ) {
    _checkpointingEnabled = checkpointingEnabled;
    _concurrentRunsEnabled = enableConcurrentRuns;
    if (!enableConcurrentRuns) {
      workflow.takeOwnership(this);
      _ownsWorkflow = true;
    }
  }

  final Workflow _workflow;
  final String _sessionId;
  final IEventSink _outgoingEvents;
  final InProcStepTracer _stepTracer;
  final OutputFilter _outputFilter;
  final MessageRouter _edgeRouter;

  late bool _checkpointingEnabled;
  late bool _concurrentRunsEnabled;
  bool _ownsWorkflow = false;
  bool _ended = false;
  bool _haltRequested = false;
  final Map<String, Object?> _traceContext = {};

  final Map<String, Executor<dynamic, dynamic>> _executors = {};
  final Map<String, List<MessageEnvelope>> _nextStep = {};
  final List<Future<void> Function()> _queuedExternalDeliveries = [];
  final Map<String, ExternalRequest<dynamic, dynamic>> _externalRequests = {};
  final Map<String, ISuperStepRunner> _joinedRunners = {};
  final Map<String, int> _requestCounters = {};

  /// Gets the state manager.
  final StateManager stateManager = StateManager();

  /// Whether an executor requested a halt via [WorkflowStateContext.requestHaltAsync].
  bool get haltRequested => _haltRequested;

  /// Gets the step tracer for this run.
  InProcStepTracer get stepTracer => _stepTracer;

  // ── SuperStepJoinContext ─────────────────────────────────────────────────

  @override
  bool get checkpointingEnabled => _checkpointingEnabled;

  @override
  bool get concurrentRunsEnabled => _concurrentRunsEnabled;

  @override
  Future<void> forwardWorkflowEventAsync(
    WorkflowEvent workflowEvent, {
    CancellationToken? cancellationToken,
  }) => _addEventAsync(workflowEvent);

  @override
  Future<void> sendMessageAsync<TMessage extends Object>(
    String senderId,
    TMessage message, {
    CancellationToken? cancellationToken,
  }) => _sendMessageAsync(senderId, message, cancellationToken: cancellationToken);

  @override
  Future<void> yieldOutputAsync<TOutput extends Object>(
    String senderId,
    TOutput output, {
    CancellationToken? cancellationToken,
  }) => _yieldOutputAsync(senderId, output, cancellationToken: cancellationToken);

  @override
  Future<String> attachSuperstepAsync(
    ISuperStepRunner superStepRunner, {
    CancellationToken? cancellationToken,
  }) {
    String joinId;
    do {
      joinId = clock.now().microsecondsSinceEpoch.toRadixString(16);
    } while (_joinedRunners.containsKey(joinId));
    _joinedRunners[joinId] = superStepRunner;
    return Future.value(joinId);
  }

  @override
  Future<bool> detachSuperstepAsync(String joinId) {
    return Future.value(_joinedRunners.remove(joinId) != null);
  }

  // ── executor lifecycle ───────────────────────────────────────────────────

  /// Returns (creating if needed) the executor with [executorId].
  Future<Executor<dynamic, dynamic>> ensureExecutorAsync(
    String executorId, {
    IStepTracer? tracer,
    CancellationToken? cancellationToken,
  }) async {
    _checkEnded();
    if (_executors.containsKey(executorId)) return _executors[executorId]!;

    final binding = _findBinding(executorId);
    final executor = await binding.createInstance();
    _executors[executorId] = executor;
    tracer?.traceInstantiated(executorId);
    return executor;
  }

  ExecutorBinding _findBinding(String executorId) {
    for (final binding in _workflow.reflectExecutors()) {
      if (binding.id == executorId) return binding;
    }
    throw StateError(
      "Executor with ID '$executorId' is not registered in this workflow.",
    );
  }

  // ── external input ───────────────────────────────────────────────────────

  /// Queues an external [message] for delivery to the workflow.
  void addExternalMessage(Object message) {
    _checkEnded();
    _queuedExternalDeliveries.add(() async {
      final envelope = MessageEnvelope(
        targetExecutorId: _workflow.startExecutorId,
        message: message,
      );
      _nextStep
          .putIfAbsent(_workflow.startExecutorId, () => [])
          .add(envelope);
    });
  }

  /// Queues an external [response] for delivery to the waiting executor.
  void addExternalResponse(ExternalResponse<dynamic> response) {
    _checkEnded();
    _queuedExternalDeliveries.add(() async {
      _completeRequest(response.requestId);
      final portId = response.port.id;
      for (final entry in _executors.entries) {
        final executor = entry.value;
        if (executor.canAccept(response.response?.runtimeType ?? Null)) {
          final envelope = MessageEnvelope(
            targetExecutorId: entry.key,
            message: response.response,
          );
          _nextStep.putIfAbsent(entry.key, () => []).add(envelope);
          return;
        }
      }
      throw StateError(
        'No executor found to handle response for port "$portId".',
      );
    });
  }

  bool _completeRequest(String requestId) =>
      _externalRequests.remove(requestId) != null;

  // ── step management ──────────────────────────────────────────────────────

  /// Whether there are messages queued for the next superstep.
  bool get hasQueuedMessages => _nextStep.isNotEmpty;

  /// Whether there are pending external deliveries.
  bool get hasQueuedExternalDeliveries => _queuedExternalDeliveries.isNotEmpty;

  /// Whether joined sub-workflow runners have pending work.
  bool get joinedRunnersHaveActions =>
      _joinedRunners.values.any((r) => r.hasUnprocessedMessages);

  /// Whether the next superstep has any work to do.
  bool get nextStepHasActions =>
      hasQueuedMessages ||
      hasQueuedExternalDeliveries ||
      joinedRunnersHaveActions;

  /// Whether there are unserviced external requests.
  bool get hasUnservicedRequests =>
      _externalRequests.isNotEmpty ||
      _joinedRunners.values.any((r) => r.hasUnservicedRequests);

  /// Applies all queued external deliveries then swaps and returns the current
  /// step's message queue.
  Future<Map<String, List<MessageEnvelope>>> advanceAsync() async {
    _checkEnded();
    while (_queuedExternalDeliveries.isNotEmpty) {
      final delivery = _queuedExternalDeliveries.removeAt(0);
      await delivery();
    }
    final current = Map<String, List<MessageEnvelope>>.of(_nextStep);
    _nextStep.clear();
    return current;
  }

  // ── message routing (internal) ───────────────────────────────────────────

  Future<void> _sendMessageAsync(
    String sourceId,
    Object message, {
    String? targetId,
    CancellationToken? cancellationToken,
  }) async {
    _checkEnded();
    if (targetId != null && targetId.isNotEmpty) {
      final envelope = MessageEnvelope(
        sourceExecutorId: sourceId,
        targetExecutorId: targetId,
        message: message,
      );
      _nextStep.putIfAbsent(targetId, () => []).add(envelope);
      return;
    }
    for (final envelope in _edgeRouter.route(sourceId, message)) {
      _nextStep.putIfAbsent(envelope.targetExecutorId, () => []).add(envelope);
    }
  }

  int _nextRequestCount(String executorId) =>
      _requestCounters.update(executorId, (c) => c + 1, ifAbsent: () => 1);

  Future<void> _yieldOutputAsync(
    String sourceId,
    Object output, {
    CancellationToken? cancellationToken,
  }) async {
    _checkEnded();
    if (_outputFilter.canOutput(sourceId, output)) {
      await _addEventAsync(WorkflowOutputEvent(executorId: sourceId, data: output));
    }
  }

  Future<void> _addEventAsync(WorkflowEvent event) =>
      _outgoingEvents.enqueue(event);

  // ── lifecycle ────────────────────────────────────────────────────────────

  /// Republishes all unserviced external request events.
  Future<void> republishUnservicedRequestsAsync({
    CancellationToken? cancellationToken,
  }) async {
    _checkEnded();
    for (final request in _externalRequests.values) {
      await _addEventAsync(RequestInfoEvent(request));
    }
  }

  /// Posts a new external request to the event sink and registers it as
  /// pending.
  Future<void> postExternalRequestAsync(
    ExternalRequest<dynamic, dynamic> request,
  ) async {
    _checkEnded();
    if (_externalRequests.containsKey(request.requestId)) {
      throw ArgumentError(
        "Pending request '${request.requestId}' already exists.",
      );
    }
    _externalRequests[request.requestId] = request;
    await _addEventAsync(RequestInfoEvent(request));
  }

  // ── checkpoint export/import ─────────────────────────────────────────────

  /// Exports runner state for checkpointing.
  ({
    List<String> instantiatedExecutors,
    Map<String, List<MessageEnvelope>> queuedMessages,
    List<ExternalRequest<dynamic, dynamic>> outstandingRequests,
  }) exportState() {
    _checkEnded();
    return (
      instantiatedExecutors: List<String>.of(_executors.keys),
      queuedMessages: Map<String, List<MessageEnvelope>>.of(_nextStep),
      outstandingRequests: List.of(_externalRequests.values),
    );
  }

  /// Restores runner state from a previous export.
  Future<void> importStateAsync({
    required List<String> instantiatedExecutors,
    required Map<String, List<MessageEnvelope>> queuedMessages,
    required List<ExternalRequest<dynamic, dynamic>> outstandingRequests,
    CancellationToken? cancellationToken,
  }) async {
    _checkEnded();
    _queuedExternalDeliveries.clear();
    _nextStep
      ..clear()
      ..addAll(queuedMessages);
    _externalRequests.clear();
    for (final req in outstandingRequests) {
      _externalRequests[req.requestId] = req;
    }
    for (final id in instantiatedExecutors) {
      if (!_executors.containsKey(id)) {
        await ensureExecutorAsync(id, cancellationToken: cancellationToken);
      }
    }
  }

  // ── workflow context factory ─────────────────────────────────────────────

  /// Creates a [WorkflowStateContext] bound to [executorId].
  WorkflowStateContext bindWorkflowContext(String executorId) =>
      _BoundContext(this, executorId);

  // ── run end ──────────────────────────────────────────────────────────────

  /// Ends the run and releases workflow ownership.
  Future<void> endRunAsync() async {
    if (_ended) return;
    _ended = true;
    if (_ownsWorkflow) {
      await _workflow.releaseOwnership(this, null);
      _ownsWorkflow = false;
    }
  }

  void _checkEnded() {
    if (_ended) {
      throw StateError(
        "Workflow run for session '$_sessionId' has been ended.",
      );
    }
  }

  /// The sub-workflow runners that have joined this execution context.
  Iterable<ISuperStepRunner> get joinedSubworkflowRunners => _joinedRunners.values;
}

// ── private ──────────────────────────────────────────────────────────────────

class _BoundContext implements WorkflowStateContext {
  _BoundContext(this._ctx, this.executorId);

  final InProcessRunnerContext _ctx;

  @override
  final String executorId;

  @override
  Future<void> sendMessage<T>(
    T message, {
    String? targetExecutorId,
    CancellationToken? cancellationToken,
  }) => _ctx._sendMessageAsync(
    executorId,
    message as Object,
    targetId: targetExecutorId,
    cancellationToken: cancellationToken,
  );

  @override
  Future<void> yieldOutput<T>(
    T output, {
    CancellationToken? cancellationToken,
  }) => _ctx._yieldOutputAsync(
    executorId,
    output as Object,
    cancellationToken: cancellationToken,
  );

  @override
  Future<ExternalResponse<TResponse>> sendRequest<TRequest, TResponse>(
    RequestPort<TRequest, TResponse> port,
    TRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final requestId = '$executorId-${_ctx._nextRequestCount(executorId)}';
    final externalRequest = ExternalRequest<TRequest, TResponse>(
      requestId: requestId,
      port: port,
      request: request,
    );
    await _ctx.postExternalRequestAsync(externalRequest);
    // The response arrives later via addExternalResponse / advanceAsync.
    // Return a placeholder; the caller must await a future superstep.
    return ExternalResponse<TResponse>(
      requestId: requestId,
      port: port.toDescriptor(),
      response: null as TResponse,
    );
  }

  // ── state ────────────────────────────────────────────────────────────────

  @override
  T? readState<T>(String key, {String? scopeName}) =>
      _ctx.stateManager.readState<T>(executorId, scopeName, key);

  @override
  T readOrInitState<T>(String key, T Function() factory, {String? scopeName}) =>
      _ctx.stateManager.readOrInitState(executorId, scopeName, key, factory);

  @override
  Set<String> readStateKeys({String? scopeName}) =>
      _ctx.stateManager.readKeys(executorId, scopeName);

  @override
  void queueStateUpdate<T>(String key, T? value, {String? scopeName}) =>
      _ctx.stateManager.writeState(executorId, scopeName, key, value);

  @override
  void queueClearScope({String? scopeName}) =>
      _ctx.stateManager.clearScope(executorId, scopeName);

  @override
  Future<void> addEventAsync(
    WorkflowEvent event, {
    CancellationToken? cancellationToken,
  }) => _ctx._addEventAsync(event);

  @override
  Future<void> requestHaltAsync({CancellationToken? cancellationToken}) {
    _ctx._haltRequested = true;
    return Future.value();
  }

  @override
  Map<String, Object?> get traceContext => _ctx._traceContext;

  @override
  bool get concurrentRunsEnabled => _ctx._concurrentRunsEnabled;

  @override
  SuperStepJoinContext get superstepJoinContext => _ctx;
}

