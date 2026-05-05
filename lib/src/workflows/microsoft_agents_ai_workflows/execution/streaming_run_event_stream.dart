import 'package:extensions/system.dart';
import '../observability/event_names.dart';
import '../observability/tags.dart';
import '../request_halt_event.dart';
import '../run.dart';
import '../run_status.dart';
import '../workflow_error_event.dart';
import '../workflow_event.dart';
import '../workflow_started_event.dart';
import 'async_run_handle.dart';
import 'input_waiter.dart';
import 'run_event_stream.dart';
import 'super_step_runner.dart';
import '../../../activity_stubs.dart';

/// A modern implementation of IRunEventStream that streams events as they are
/// created, using System.Threading.Channels for thread-safe coordination.
class StreamingRunEventStream implements RunEventStream {
  StreamingRunEventStream(
    SuperStepRunner stepRunner,
    {bool? disableRunLoop = null, },
  ) : _stepRunner = stepRunner {
    this._runLoopCancellation = cancellationTokenSource();
    this._inputWaiter = new();
    this._disableRunLoop = disableRunLoop;
    // Unbounded channel - events never block the producer
        // This allows events to flow freely during superstep execution
        this._eventChannel = Channel.createUnbounded<WorkflowEvent>(unboundedChannelOptions());
  }

  late final Channel<WorkflowEvent> _eventChannel;

  final SuperStepRunner _stepRunner;

  late final InputWaiter _inputWaiter;

  late final CancellationTokenSource _runLoopCancellation;

  late final bool _disableRunLoop;

  Future? _runLoopFuture;

  RunStatus _runStatus = RunStatus.NotStarted;

  int _completionEpoch;

  @override
  void start() {
    if (!this._disableRunLoop) {
      this._runLoopTask = Task.run(() => this.runLoopAsync(this._runLoopCancellation.token));
    }
  }

  Future runLoop(CancellationToken cancellationToken) async  {
    var errorSource = new();
    var linkedSource = CancellationTokenSource.createLinkedTokenSource(
      errorSource.token,
      cancellationToken,
    );
    // Subscribe to events - they will flow directly to the channel as they're raised
        this._stepRunner.outgoingEvents.eventRaised += OnEventRaisedAsync;
    // Re-emit any pending external requests that were restored from a checkpoint
        // before this subscription was active. For non-resume starts this is a no-op.
        await this._stepRunner.republishPendingEventsAsync(linkedSource.token);
    var sessionActivity = this._stepRunner.telemetryContext.startWorkflowSessionActivity();
    sessionActivity?.setTag(Tags.workflowId, this._stepRunner.startExecutorId)
                        .setTag(Tags.sessionId, this._stepRunner.sessionId);
    var runActivity = null;
    sessionActivity?.addEvent(activityEvent(EventNames.sessionStarted));
    try {
      // Wait for the first input before starting.
            // The consumer will call EnqueueMessageAsync which signals the run loop.
            // Note: AsyncRunHandle also signals here on checkpoint resume when there are
            // already pending requests, so the first iteration can emit a PendingRequests
            // halt signal even without unprocessed messages.
            await this._inputWaiter.waitForInputAsync(cancellationToken: linkedSource.token);
      while (!linkedSource.token.isCancellationRequested) {
        // Start a new run-stage activity for this input→processing→halt cycle
                runActivity = this._stepRunner.telemetryContext.startWorkflowRunActivity();
        runActivity?.setTag(Tags.workflowId, this._stepRunner.startExecutorId)
                            .setTag(Tags.sessionId, this._stepRunner.sessionId);
        runActivity?.addEvent(activityEvent(EventNames.workflowStarted));
        if (this._stepRunner.hasUnprocessedMessages) {
          // Flip to Running only when there's actual work to process.
                    // This is intentionally inside the HasUnprocessedMessages branch so
                    // that stale input signals cannot transiently flip status back to
                    // Running after a prior halt has already been observed by callers
                    // (e.g. Run.resumeAsync returning after reading an Idle halt signal).
                    this._runStatus = RunStatus.running;
          // Emit WorkflowStartedEvent only when there's actual work to process
                    // This avoids spurious events on timeout-only loop iterations
                    await this._eventChannel.writer.writeAsync(
                      workflowStartedEvent(),
                      linkedSource.token,
                    ) ;
          while (this._stepRunner.hasUnprocessedMessages && !linkedSource.token.isCancellationRequested) {
            await this._stepRunner.runSuperStepAsync(linkedSource.token);
          }
        }
        // Update status based on what's waiting
                this._runStatus = this._stepRunner.hasUnservicedRequests
                    ? RunStatus.pendingRequests
                    : RunStatus.idle;
        var currentEpoch = (++this._completionEpoch);
        var capturedStatus = this._runStatus;
        await this._eventChannel.writer.writeAsync(
          internalHaltSignal(currentEpoch, capturedStatus),
          linkedSource.token,
        ) ;
        if (runActivity != null) {
          runActivity.addEvent(activityEvent(EventNames.workflowCompleted));
          runActivity.dispose();
          runActivity = null;
        }
        // Wait for next input from the consumer
                // Works for both idle(no work) and pendingRequests(waiting for responses)
                await this._inputWaiter.waitForInputAsync(linkedSource.token);
      }
    } catch (e, s) {
      if (e is OperationCanceledException) {
        final  = e as OperationCanceledException;
        {}
      } else   if (e is Exception) {
        final ex = e as Exception;
        {
          if (runActivity != null) {
            runActivity.addEvent(activityEvent(EventNames.workflowError, tags: new(),
                             { Tags.errorMessage, ex.message },
                        }));
          runActivity.captureException(ex);
        }
        if (sessionActivity != null) {
          sessionActivity.addEvent(activityEvent(EventNames.sessionError, tags: new(),
                             { Tags.errorMessage, ex.message },
                        }));
        sessionActivity.captureException(ex);
      }
      await this._eventChannel.writer.writeAsync(
        workflowErrorEvent(ex),
        linkedSource.token,
      ) ;
    }
  } else {
    rethrow;
  }

  } finally {
  this._stepRunner.outgoingEvents.eventRaised -= OnEventRaisedAsync;
  this._eventChannel.writer.complete();
  // Mark as ended when run loop exits
            this._runStatus = RunStatus.ended;
  if (runActivity != null) {
    runActivity.addEvent(activityEvent(EventNames.workflowCompleted));
    runActivity.dispose();
  }

  if (sessionActivity != null) {
    sessionActivity.addEvent(activityEvent(EventNames.sessionCompleted));
    sessionActivity.dispose();
  }
}
/* TODO: unsupported node kind "unknown" */
// async ValueTask OnEventRaisedAsync(Object? sender, WorkflowEvent e)
//         {
//             // Write event directly to channel - it's thread-safe and non-blocking
//             // The channel handles all synchronization internally using lock-free algorithms
//             // Events flow immediately to consumers rather than being batched
//             await this._eventChannel.Writer.WriteAsync(e, linkedSource.Token);
//
//             if (e is WorkflowErrorEvent error)
//             {
//                 errorSource.Cancel();
//             }
//         }
 }
/// Signals that new input has been provided and the run loop should continue
/// processing. Called by AsyncRunHandle when the user enqueues a message or
/// response.
@override
void signalInput() {
this._inputWaiter.signalInput();
 }
@override
Stream<WorkflowEvent> takeEventStream(
  bool blockOnPendingRequest,
  {CancellationToken? cancellationToken, },
) async  {
var currentEpoch = Volatile.read(_completionEpoch);
var expectingFreshWork = this._stepRunner.hasUnprocessedMessages || this._runStatus == RunStatus.running;
var myEpoch = expectingFreshWork ? currentEpoch + 1 : currentEpoch;
var eventStream = new(this._eventChannel.reader);
for (final evt in eventStream.withCancellation(cancellationToken)) {
  if (evt is InternalHaltSignal) {
      final completionSignal = evt as InternalHaltSignal;
      if (completionSignal.epoch < myEpoch) {
        continue;
      }
      if (cancellationToken.isCancellationRequested) {
        return;
      }
      if (completionSignal.status is RunStatus.idle or RunStatus.ended) {
        return;
      }
      if (!blockOnPendingRequest && completionSignal.status is RunStatus.pendingRequests) {
        return;
      }
      continue;
    }
  if (evt is RequestHaltEvent) {
    return;
  }

  if (cancellationToken.isCancellationRequested) {
    return;
  }

  yield evt;
}
 }
@override
Future<RunStatus> getStatus({CancellationToken? cancellationToken}) {
return Future<RunStatus>(this._runStatus);
 }
/// Clears all buffered events from the channel. This should be called when
/// restoring a checkpoint to discard stale events from superseded supersteps.
void clearBufferedEvents() {
while (this._eventChannel.reader.tryRead(_)) {}
 }
@override
Future stop() async  {
// Cancel the run loop
        this._runLoopCancellation.cancel();
// Release the event waiter, if any
        this._inputWaiter.signalInput();
if (this._runLoopTask != null) {
  try {
    await this._runLoopTask;
  } catch (e, s) {
    if (e is OperationCanceledException) {
      final  = e as OperationCanceledException;
      {}
    } else {
      rethrow;
  }
  }
}
 }
@override
Future dispose() async  {
await this.stopAsync();
// Dispose resources
        this._runLoopCancellation.dispose();
this._inputWaiter.dispose();
 }
 }
/// Internal signal used to mark completion of a work batch and allow status
/// checking. This is never exposed to consumers.
class InternalHaltSignal extends WorkflowEvent {
  /// Internal signal used to mark completion of a work batch and allow status
  /// checking. This is never exposed to consumers.
  const InternalHaltSignal(int epoch, RunStatus status, ) : epoch = epoch, status = status;

  int get epoch {
    return epoch;
  }

  RunStatus get status {
    return status;
  }
}
