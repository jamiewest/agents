import 'dart:collection';
import 'package:extensions/system.dart';
import '../../microsoft_agents_ai_purview/models/common/activity.dart';
import '../observability/event_names.dart';
import '../observability/tags.dart';
import '../request_halt_event.dart';
import '../run_status.dart';
import '../workflow_event.dart';
import '../workflow_started_event.dart';
import 'input_waiter.dart';
import 'run_event_stream.dart';
import 'super_step_runner.dart';
import '../../../activity_stubs.dart';

class LockstepRunEventStream implements RunEventStream {
  LockstepRunEventStream(SuperStepRunner stepRunner) : _stepRunner = stepRunner {
  }

  final CancellationTokenSource _stopCancellation;

  final InputWaiter _inputWaiter;

  Queue<WorkflowEvent> _eventSink;

  int _isDisposed;

  final SuperStepRunner _stepRunner;

  late Activity? _sessionActivity;

  RunStatus runStatus = RunStatus.NotStarted;

  @override
  Future<RunStatus> getStatus({CancellationToken? cancellationToken}) {
    return new(this.runStatus);
  }

  @override
  void start() {
    var previousActivity = Activity.current;
    this._stepRunner.outgoingEvents.eventRaised += this.onWorkflowEventAsync;
    this._sessionActivity = this._stepRunner.telemetryContext.startWorkflowSessionActivity();
    this._sessionActivity?.setTag(Tags.workflowId, this._stepRunner.startExecutorId)
                              .setTag(Tags.sessionId, this._stepRunner.sessionId);
    this._sessionActivity?.addEvent(activityEvent(EventNames.sessionStarted));
    Activity.current = previousActivity;
  }

  @override
  Stream<WorkflowEvent> takeEventStream(
    bool blockOnPendingRequest,
    {CancellationToken? cancellationToken, },
  ) async  {
    if (Volatile.read(_isDisposed) == 1) {
      throw objectDisposedException('LockstepRunEventStream');
    }
    var linkedSource = CancellationTokenSource.createLinkedTokenSource(
      this._stopCancellation.token,
      cancellationToken,
    );
    // Re-establish session as parent so the run activity nests correctly.
        Activity.current = this._sessionActivity;
    var runActivity = this._stepRunner.telemetryContext.startWorkflowRunActivity();
    runActivity?.setTag(
      Tags.workflowId,
      this._stepRunner.startExecutorId,
    ) .setTag(Tags.sessionId, this._stepRunner.sessionId);
    try {
      this.runStatus = runStatus.running;
      runActivity?.addEvent(activityEvent(EventNames.workflowStarted));
      // Emit WorkflowStartedEvent to the event stream for consumers
            this._eventSink.enqueue(workflowStartedEvent());
      // Re-emit any pending external requests that were restored from a checkpoint
            // before this subscription was active. For non-resume starts this is a no-op.
            // This runs after WorkflowStartedEvent so consumers always see the started event first.
            await this._stepRunner.republishPendingEventsAsync(linkedSource.token);
      if (!this._stepRunner.hasUnprocessedMessages) {
        var (drainedEvents, shouldHalt) = this.drainAndFilterEvents();
        for (final raisedEvent in drainedEvents) {
          yield raisedEvent;
        }
        if (shouldHalt) {
          return;
        }
        this.runStatus = this._stepRunner.hasUnservicedRequests ? runStatus.pendingRequests : runStatus.idle;
      }
      do {
        while (this._stepRunner.hasUnprocessedMessages &&
                       !linkedSource.token.isCancellationRequested) {
          // Because we may be yielding this function, we need to ensure that the Activity.current
                    // is set to our activity for the duration of this loop iteration.
                    Activity.current = runActivity;
          try {
            await this._stepRunner.runSuperStepAsync(linkedSource.token);
          } catch (e, s) {
            if (e is OperationCanceledException) {
              final  = e as OperationCanceledException;
              {}
            } else         if (e is Exception) {
              final ex = e as Exception;
              {
                runActivity.addEvent(activityEvent(EventNames.workflowError, tags: new(),
                             { Tags.errorMessage, ex.message },
                        }));
              runActivity.captureException(ex);
              rethrow;
            }
          } else {
            rethrow;
          }
        }
        if (linkedSource.token.isCancellationRequested) {
          return;
        }
        var (drainedEvents, shouldHalt) = this.drainAndFilterEvents();
        for (final raisedEvent in drainedEvents) {
          if (linkedSource.token.isCancellationRequested) {
            return;
          }
          yield raisedEvent;
        }
        if (shouldHalt || linkedSource.token.isCancellationRequested) {
          return;
        }
        this.runStatus = this._stepRunner.hasUnservicedRequests ? runStatus.pendingRequests : runStatus.idle;
      }
      if (blockOnPendingRequest && this.runStatus == runStatus.pendingRequests) {
        try {
          await this._inputWaiter.waitForInputAsync(
            TimeSpan.fromSeconds(1),
            linkedSource.token,
          ) ;
        } catch (e, s) {
          if (e is OperationCanceledException) {
            final  = e as OperationCanceledException;
            {}
          } else {
            rethrow;
          }
        }
      }
    } while (!shouldBreak());
    runActivity?.addEvent(activityEvent(EventNames.workflowCompleted));
  } finally {
    this.runStatus = this._stepRunner.hasUnservicedRequests ? runStatus.pendingRequests : runStatus.idle;
    // Explicitly dispose the Activity so Activity.stop fires deterministically,
            // regardless of how the async iterator enumerator is disposed.
            runActivity?.dispose();
  }

  /* TODO: unsupported node kind "unknown" */
  // // If we are Idle or Ended, we should break the loop
  //         // If we are PendingRequests and not blocking on pending requests, we should break the loop
  //         // If cancellation is requested, we should break the loop
  //         bool ShouldBreak() => this.RunStatus is RunStatus.Idle or RunStatus.Ended ||
  //                                (this.RunStatus == RunStatus.PendingRequests && !blockOnPendingRequest) ||
  //                                linkedSource.Token.IsCancellationRequested;
}
void clearBufferedEvents() {
(() { final _old = this._eventSink; this._eventSink = Queue<WorkflowEvent>(; return _old; })());
 }
/// Signals that new input has been provided and the run loop should continue
/// processing. Called by AsyncRunHandle when the user enqueues a message or
/// response.
@override
void signalInput() {
this._inputWaiter?.signalInput();
 }
@override
Future stop() {
this._stopCancellation.cancel();
return Future.value();
 }
@override
Future dispose() {
if ((() { final _old = this._isDisposed; this._isDisposed = 1; return _old; })() == 0) {
  this._stopCancellation.cancel();
  this._stepRunner.outgoingEvents.eventRaised -= this.onWorkflowEventAsync;
  if (this._sessionActivity != null) {
    this._sessionActivity.addEvent(activityEvent(EventNames.sessionCompleted));
    this._sessionActivity.dispose();
    this._sessionActivity = null;
  }

  this._stopCancellation.dispose();
  this._inputWaiter.dispose();
}
return Future.value();
 }
Future onWorkflowEvent(Object? sender, WorkflowEvent e, ) {
this._eventSink.enqueue(e);
return Future.value();
 }
ListWorkflowEventEventsboolShouldHalt drainAndFilterEvents() {
var events = [];
var shouldHalt = false;
for (final e in (() { final _old = this._eventSink; this._eventSink = Queue<WorkflowEvent>(; return _old; })())) {
  if (e is RequestHaltEvent) {
    shouldHalt = true;
  } else {
    events.add(e);
  }
}
return (events, shouldHalt);
 }
 }
