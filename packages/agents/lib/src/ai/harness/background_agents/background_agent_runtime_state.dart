import 'dart:async';

import 'package:extensions/system.dart';

import '../../../abstractions/agent_response.dart';
import '../../../abstractions/agent_session.dart';
import 'background_agents_provider.dart';

/// Holds non-serializable runtime references for in-flight background tasks
/// within a single parent session.
///
/// Runtime task state is not JSON-serializable. After deserialization (e.g.,
/// after a restart), a fresh empty instance is created and any
/// previously-running tasks are marked as lost by [BackgroundAgentsProvider].
class BackgroundAgentRuntimeState {
  BackgroundAgentRuntimeState();

  /// Gets the mapping of task IDs to their in-flight [Future] instances.
  final Map<int, BackgroundAgentRuntimeTask> inFlightTasks = {};

  /// Gets the mapping of task IDs to their background agent [AgentSession]
  /// instances, needed for `ContinueTask`.
  final Map<int, AgentSession> backgroundTaskSessions = {};

  /// Gets the mapping of task IDs to the [CancellationTokenSource]
  /// controlling their run.
  ///
  /// A source is created when a task is started or continued, and is disposed
  /// and removed when the task is finalized, cleared, or when the session is
  /// released via [BackgroundAgentsProvider.releaseSession].
  final Map<int, CancellationTokenSource> taskCancellations = {};

  /// Whether this runtime has been released via
  /// [BackgroundAgentsProvider.releaseSession].
  ///
  /// Once released, all in-flight tasks have been cancelled and awaited, and
  /// the runtime references have been dropped. Tools that would start new
  /// background work refuse to run against a released runtime.
  bool isReleased = false;

  /// The completion signalled once the release of this runtime has finished
  /// all of its cleanup.
  ///
  /// Set by the caller that first releases the runtime, and completed once
  /// that caller has finished waiting for the in-flight tasks and has dropped
  /// the runtime references. Callers that arrive while a release is already
  /// in progress await this instead of returning early, so that a completed
  /// [BackgroundAgentsProvider.releaseSession] always means the cleanup is
  /// done. It is completed successfully even when the releasing caller fails,
  /// because a waiter should observe that cleanup finished rather than
  /// inherit another caller's failure.
  Completer<void>? releaseCompletion;
}

/// Tracks the completion state of a Dart [Future] while preserving the C#
/// provider's explicit task-finalization shape.
class BackgroundAgentRuntimeTask {
  BackgroundAgentRuntimeTask(this.task) {
    completion = task.then<void>(
      (value) {
        isCompleted = true;
        result = value;
      },
      onError: (Object error, StackTrace stackTrace) {
        isCompleted = true;
        this.error = error;
        this.stackTrace = stackTrace;
      },
    );
  }

  /// The underlying asynchronous operation.
  final Future<AgentResponse> task;

  /// Completes after [task] has either produced a result or captured an error.
  late final Future<void> completion;

  /// Whether [task] has completed.
  bool isCompleted = false;

  /// The result from a completed task, if successful.
  AgentResponse? result;

  /// The error from a completed task, if failed.
  Object? error;

  /// The stack trace from a completed task, if failed.
  StackTrace? stackTrace;
}
