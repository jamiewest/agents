import 'package:extensions/system.dart';
// TODO: import not yet ported
import '../checkpoint_info.dart';
import '../checkpointing/checkpointing_handle.dart';
import '../external_response.dart';
import '../request_halt_event.dart';
import '../run_status.dart';
import '../workflow_event.dart';
import 'execution_mode.dart';
import 'lockstep_run_event_stream.dart';
import 'run_event_stream.dart';
import 'streaming_run_event_stream.dart';
import 'super_step_runner.dart';

class AsyncRunHandle implements AsyncDisposable,CheckpointingHandle {
  AsyncRunHandle(
    SuperStepRunner stepRunner,
    CheckpointingHandle checkpointingHandle,
    ExecutionMode mode,
  ) :
      _stepRunner = stepRunner,
      _checkpointingHandle = checkpointingHandle {
    this._eventStream = mode switch
        {
            ExecutionMode.offThread => streamingRunEventStream(stepRunner),
            ExecutionMode.subworkflow => streamingRunEventStream(stepRunner, disableRunLoop: true),
            ExecutionMode.lockstep => lockstepRunEventStream(stepRunner),
            (_) => throw ArgumentError.value('mode', 'Unknown execution mode ${mode}')
        };
    this._eventStream.start();
    if (stepRunner.hasUnprocessedMessages || stepRunner.hasUnservicedRequests) {
      this.signalInputToRunLoop();
    }
  }

  final SuperStepRunner _stepRunner;

  final CheckpointingHandle _checkpointingHandle;

  late final RunEventStream _eventStream;

  final CancellationTokenSource _endRunSource;

  int _isDisposed;

  int _isEventStreamTaken;

  String get sessionId {
    return this._stepRunner.sessionId;
  }

  bool get isCheckpointingEnabled {
    return this._checkpointingHandle.isCheckpointingEnabled;
  }

  List<CheckpointInfo> get checkpoints {
    return this._checkpointingHandle.checkpoints;
  }

  Future<RunStatus> getStatus({CancellationToken? cancellationToken}) {
    return this._eventStream.getStatusAsync(cancellationToken);
  }

  (bool, String?) tryGetResponsePortExecutorId(String portId) {
    // TODO(transpiler): implement out-param body
    throw UnimplementedError();
  }

  Stream<WorkflowEvent> takeEventStream(
    bool blockOnPendingRequest,
    {CancellationToken? cancellationToken, }
  ) async* {
    if ((() { final _old = this._isEventStreamTaken; if (_old == 0) this._isEventStreamTaken = 1; return _old; })() != 0) {
      throw StateError("The event stream has already been taken. Only one enumerator is allowed at a time.");
    }
    var linked = null;
    try {
      linked = CancellationTokenSource.createLinkedTokenSource(
        cancellationToken,
        this._endRunSource.token,
      );
      var token = linked.token;
      var inner = this._eventStream.takeEventStreamAsync(blockOnPendingRequest, token);
      for (final ev in inner.withCancellation(token)) {
        if (ev is RequestHaltEvent) {
          return;
        }
        yield ev;
      }
    } finally {
      linked?.dispose();
      (() { final _old = this._isEventStreamTaken; this._isEventStreamTaken = 0; return _old; })();
    }
  }

  Future<bool> isValidInputType<T>({CancellationToken? cancellationToken}) {
    return this._stepRunner.isValidInputTypeAsync<T>(cancellationToken);
  }

  Future<bool> enqueueMessage<T>(T message, {CancellationToken? cancellationToken, }) async {
    if (message is ExternalResponse) {
      final response = message as ExternalResponse;
      // EnqueueResponseAsync handles signaling
            await this.enqueueResponseAsync(response, cancellationToken)
                      ;
      return true;
    }
    var result = await this._stepRunner.enqueueMessageAsync(message, cancellationToken)
                                            ;
    // Signal the run loop that new input is available
        this.signalInputToRunLoop();
    return result;
  }

  Future<bool> enqueueMessageUntyped(
    Object message,
    {Type? declaredType, CancellationToken? cancellationToken, }
  ) async {
    if (declaredType?.isInstanceOfType(message) == false) {
      throw ArgumentError(
        'Message is! of the declared type ${declaredType}. Actual type: ${message.runtimeType}',
        'message',
      );
    }
    if (declaredType != null && ExternalResponse.isAssignableFrom(declaredType)) {
      // EnqueueResponseAsync handles signaling
            await this.enqueueResponseAsync((ExternalResponse)message, cancellationToken)
                      ;
      return true;
    } else if (declaredType == null && message is ExternalResponse) {
      final response = declaredType == null && message as ExternalResponse;
      // EnqueueResponseAsync handles signaling
            await this.enqueueResponseAsync(response, cancellationToken)
                      ;
      return true;
    }
    var result = await this._stepRunner.enqueueMessageUntypedAsync(
      message,
      declaredType ?? message.runtimeType,
      cancellationToken,
    )
                                            ;
    // Signal the run loop that new input is available
        this.signalInputToRunLoop();
    return result;
  }

  Future enqueueResponse(
    ExternalResponse response,
    {CancellationToken? cancellationToken, }
  ) async {
    await this._stepRunner.enqueueResponseAsync(response, cancellationToken);
    // Signal the run loop that new input is available
        this.signalInputToRunLoop();
  }

  void signalInputToRunLoop() {
    this._eventStream.signalInput();
  }

  Future cancelRun() async {
    this._endRunSource.cancel();
    await this._eventStream.stopAsync();
  }

  @override
  Future dispose() async {
    if ((() { final _old = this._isDisposed; this._isDisposed = 1; return _old; })() == 0) {
      // Cancel the run if it is still running
            await this.cancelRunAsync();
      // These actually release and clean up resources
            await this._stepRunner.requestEndRunAsync();
      this._endRunSource.dispose();
      await this._eventStream.disposeAsync();
    }
  }

  @override
  Future restoreCheckpoint(
    CheckpointInfo checkpointInfo,
    {CancellationToken? cancellationToken, }
  ) async {
    if (this._eventStream is StreamingRunEventStream) {
      final streamingEventStream = this._eventStream as StreamingRunEventStream;
      streamingEventStream.clearBufferedEvents();
    } else if (this._eventStream is LockstepRunEventStream) {
      final lockstepEventStream = this._eventStream as LockstepRunEventStream;
      lockstepEventStream.clearBufferedEvents();
    }
    // Restore the workflow state through the live runtime-restore path.
        // This can re-emit pending requests into the already-active event stream.
        await this._checkpointingHandle.restoreCheckpointAsync(
          checkpointInfo,
          cancellationToken,
        ) ;
    // After restore, signal the run loop to process any restored messages. Initial resume
        // paths handle this separately when they create the event stream after restoring state.
        this.signalInputToRunLoop();
  }
}
