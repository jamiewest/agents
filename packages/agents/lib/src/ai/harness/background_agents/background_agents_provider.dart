import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../../../abstractions/provider_session_state.dart';
import '../../agent_json_utilities.dart';
import 'background_agent_runtime_state.dart';
import 'background_agent_state.dart';
import 'background_agents_provider_options.dart';
import 'background_task_info.dart';
import 'background_task_status.dart';
import 'package:agents/src/abstractions/invoking_context.dart';

/// An [AIContextProvider] that enables an agent to delegate work to
/// background agents asynchronously.
///
/// The [BackgroundAgentsProvider] allows a parent agent to start background
/// tasks on child agents, wait for their completion, and retrieve results.
/// Each background task runs in its own session and executes concurrently.
/// This provider exposes the following tools to the agent:
///
/// * `BackgroundAgents_StartTask` — Start a background task on a named agent
///   with text input. Returns the task ID.
/// * `BackgroundAgents_WaitForFirstCompletion` — Wait until the first
///   specified task completes or the configured timeout expires. A timeout
///   leaves the tasks running so the tool can be called again.
/// * `BackgroundAgents_GetTaskResults` — Retrieve the text output of a
///   completed background task.
/// * `BackgroundAgents_GetAllTasks` — List all background tasks with their
///   IDs, statuses, descriptions, and agent names.
/// * `BackgroundAgents_ContinueTask` — Send follow-up input to a completed
///   background task's session to resume work.
/// * `BackgroundAgents_ClearCompletedTask` — Remove a completed background
///   task and release its session to free memory.
///
/// Background tasks are tracked per session and keep running until they
/// complete. When a host is finished with a session it should call
/// [releaseSession] to cancel and await any in-flight tasks, so that
/// abandoned work does not continue to invoke models and tools in the
/// background.
class BackgroundAgentsProvider extends AIContextProvider {
  /// Creates a [BackgroundAgentsProvider] with the given [agents] and optional
  /// [options].
  ///
  /// Throws an [ArgumentError] when
  /// [BackgroundAgentsProviderOptions.waitTimeout] is not positive or exceeds
  /// [BackgroundAgentsProviderOptions.maximumWaitTimeout].
  BackgroundAgentsProvider(
    Iterable<AIAgent> agents, {
    BackgroundAgentsProviderOptions? options,
  }) : _agents = validateAndBuildAgentDictionary(agents) {
    _waitTimeout =
        options?.waitTimeout ??
        BackgroundAgentsProviderOptions.defaultWaitTimeout;
    if (_waitTimeout <= Duration.zero) {
      throw ArgumentError.value(
        _waitTimeout,
        'options',
        'waitTimeout must be positive',
      );
    }
    if (_waitTimeout > BackgroundAgentsProviderOptions.maximumWaitTimeout) {
      throw ArgumentError.value(
        _waitTimeout,
        'options',
        'waitTimeout must not exceed '
            '${BackgroundAgentsProviderOptions.maximumWaitTimeout.inMilliseconds}'
            ' milliseconds',
      );
    }

    final baseInstructions = options?.instructions ?? defaultInstructions;
    final agentListBuilder = options?.agentListBuilder;
    final agentListText = agentListBuilder != null
        ? agentListBuilder(_agents)
        : buildDefaultAgentListText(_agents);
    _instructions = baseInstructions.replaceAll(
      '{background_agents}',
      agentListText,
    );
    _sessionState = ProviderSessionState<BackgroundAgentState>(
      (_) => BackgroundAgentState(),
      runtimeType.toString(),
      stateRehydrator: BackgroundAgentState.fromJson,
      jsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
    _runtimeSessionState = ProviderSessionState<BackgroundAgentRuntimeState>(
      (_) => BackgroundAgentRuntimeState(),
      '${runtimeType}_Runtime',
      jsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  static const String defaultInstructions = '''
## Background Agents
You have access to background agents that can perform work on your behalf.

- Use the `BackgroundAgents_*` list of tools to start tasks on background agents and check their results.
- Creating a background task does not block, and background tasks run concurrently.
- Important: Always wait for outstanding tasks to finish before you finish processing.
- Important: After retrieving results from a completed task, clear it with BackgroundAgents_ClearCompletedTask to free memory, unless you plan to continue it with BackgroundAgents_ContinueTask.

{background_agents}
''';

  static const String _releasedRuntimeStartError =
      'Error: The background agents runtime for this session has been released. No new background tasks can be started.';

  static const String _releasedRuntimeContinueError =
      'Error: The background agents runtime for this session has been released. Background tasks can no longer be continued.';

  static const String _releasedTaskCanceledMessage =
      'Task was canceled because the session was released.';

  /// Sentinel passed as the `timeout` of [releaseSession] to wait
  /// indefinitely for cancelled tasks to finish (mirrors the C#
  /// `Timeout.InfiniteTimeSpan`).
  static const Duration infiniteReleaseTimeout = Duration(milliseconds: -1);

  static const Duration _defaultReleaseTimeout = Duration(seconds: 30);

  final Map<String, AIAgent> _agents;

  late final ProviderSessionState<BackgroundAgentState> _sessionState;

  late final ProviderSessionState<BackgroundAgentRuntimeState>
  _runtimeSessionState;

  late final String _instructions;

  late final Duration _waitTimeout;

  List<String>? _stateKeys;

  @override
  List<String> get stateKeys {
    return _stateKeys ??= [
      _sessionState.stateKey,
      _runtimeSessionState.stateKey,
    ];
  }

  /// Returns the background tasks for [session] that are still running.
  ///
  /// Completed, failed, and lost tasks are terminal and are not included.
  /// Used by `BackgroundTaskCompletionLoopEvaluator` to keep a loop agent
  /// iterating until all background work has finished.
  List<BackgroundTaskInfo> getIncompleteTasks(AgentSession? session) {
    final state = _sessionState.getOrInitializeState(session);
    return [
      for (final task in state.tasks)
        if (task.status == BackgroundTaskStatus.running) task,
    ];
  }

  /// Releases all runtime state held for [session], cancelling and awaiting
  /// any in-flight background tasks.
  ///
  /// Background tasks continue to execute — invoking models and tools — even
  /// after a host stops using the session that started them. Hosts should
  /// call this method when a conversation ends, or from their own eviction
  /// policy, so that abandoned work is stopped instead of running to
  /// completion with results nobody will read.
  ///
  /// [cancelRunning] is `true` to cancel any background tasks that are still
  /// running; `false` to require that all background tasks have already
  /// completed (a [StateError] is thrown otherwise). [timeout] bounds how
  /// long to wait for cancelled tasks to finish — 30 seconds by default; pass
  /// [infiniteReleaseTimeout] to wait indefinitely. If the timeout elapses,
  /// the remaining tasks are abandoned rather than blocking the caller.
  ///
  /// This method is idempotent: releasing an already-released session does
  /// nothing. Once released, the `BackgroundAgents_StartTask` and
  /// `BackgroundAgents_ContinueTask` tools refuse to run for that session,
  /// and any tasks that were still running are recorded as
  /// [BackgroundTaskStatus.failed] so a restored session does not report
  /// phantom running work.
  ///
  /// It is also safe to call concurrently. A caller that arrives while
  /// another release of the same session is still in progress waits for that
  /// release to finish rather than returning early, so a completed call
  /// always means the background tasks have been cancelled, awaited and
  /// cleaned up. Such a caller observes only its own [cancellationToken]; it
  /// neither inherits the in-progress release's failure nor is held up by
  /// that caller's [timeout].
  Future<void> releaseSession(
    AgentSession session, {
    bool cancelRunning = true,
    Duration? timeout,
    CancellationToken? cancellationToken,
  }) async {
    final effectiveTimeout = timeout ?? _defaultReleaseTimeout;
    if (effectiveTimeout < Duration.zero &&
        effectiveTimeout != infiniteReleaseTimeout) {
      throw ArgumentError.value(
        effectiveTimeout,
        'timeout',
        'The timeout must not be negative, unless it is '
            'infiniteReleaseTimeout.',
      );
    }

    final runtimeState = _runtimeSessionState.getOrInitializeState(session);
    final state = _sessionState.getOrInitializeState(session);

    if (runtimeState.isReleased) {
      // A release is already in progress or has completed. Await it rather
      // than returning early, so that a completed call always means the
      // in-flight tasks have been cancelled, awaited and cleaned up.
      final releaseInProgress = runtimeState.releaseCompletion?.future;
      if (releaseInProgress != null) {
        await _awaitReleaseInProgress(releaseInProgress, cancellationToken);
      }
      return;
    }

    final trackedTasks = Map<int, BackgroundAgentRuntimeTask>.of(
      runtimeState.inFlightTasks,
    );

    // Snapshot which tasks were still pending before anything is cancelled.
    // Tasks that had already finished keep their real outcome; only these
    // pending ones are reported as released.
    final pendingTaskIds = <int>{
      for (final entry in trackedTasks.entries)
        if (!entry.value.isCompleted) entry.key,
    };

    if (!cancelRunning && pendingTaskIds.isNotEmpty) {
      throw StateError(
        'Cannot release the session because ${pendingTaskIds.length} '
        'background task(s) are still running. Pass cancelRunning: true to '
        'cancel them.',
      );
    }

    // Cancel before publishing the release. If cancelling throws, the runtime
    // is left un-released so that the caller can retry, rather than being
    // flagged as released with tasks still running.
    for (final taskId in pendingTaskIds) {
      final cts = runtimeState.taskCancellations[taskId];
      if (cts != null) {
        try {
          cts.cancel();
        } on ObjectDisposedException {
          // The source was already disposed by a concurrent finalization;
          // nothing to cancel.
        }
      }
    }

    final releaseCompletion = Completer<void>();
    runtimeState.releaseCompletion = releaseCompletion;
    runtimeState.isReleased = true;

    try {
      await _waitForTasks(
        trackedTasks.values,
        effectiveTimeout,
        cancellationToken,
      );
    } finally {
      // Finalize every tracked task that actually finished, so successful
      // results and real failure reasons are preserved rather than being
      // overwritten with a release failure.
      for (final entry in trackedTasks.entries) {
        final tracked = _firstOrNull(state.tasks, (t) => t.id == entry.key);
        if (tracked == null ||
            tracked.status != BackgroundTaskStatus.running ||
            !entry.value.isCompleted) {
          continue;
        }

        finalizeTask(tracked, entry.value, runtimeState);

        if (entry.value.error is OperationCanceledException &&
            pendingTaskIds.contains(entry.key)) {
          // Report the actual reason rather than the generic cancellation
          // message.
          tracked.errorText = _releasedTaskCanceledMessage;
        }
      }

      for (final taskId in runtimeState.taskCancellations.keys.toList()) {
        _disposeTaskCancellation(runtimeState, taskId);
      }

      runtimeState.inFlightTasks.clear();
      runtimeState.backgroundTaskSessions.clear();

      // Anything still running was abandoned (for example after the timeout
      // elapsed).
      for (final task in state.tasks) {
        if (task.status == BackgroundTaskStatus.running) {
          task.status = BackgroundTaskStatus.failed;
          task.errorText = _releasedTaskCanceledMessage;
        }
      }

      _sessionState.saveState(session, state);
      _runtimeSessionState.saveState(session, runtimeState);

      // Signalled last so that any caller awaiting this release observes
      // fully cleaned-up state. Completed successfully even when this caller
      // failed, because the cleanup above always runs.
      if (!releaseCompletion.isCompleted) {
        releaseCompletion.complete();
      }
    }
  }

  /// Waits for a release that another caller started to finish its cleanup,
  /// giving up if the caller's own [cancellationToken] is signalled.
  static Future<void> _awaitReleaseInProgress(
    Future<void> releaseInProgress,
    CancellationToken? cancellationToken,
  ) async {
    if (cancellationToken == null || !cancellationToken.canBeCanceled) {
      // The release completion is never faulted or cancelled, so awaiting it
      // cannot throw.
      await releaseInProgress;
      return;
    }

    // Do not let this caller be held up by the releasing caller's timeout.
    var released = false;
    final cancelled = Completer<void>();
    final registration = cancellationToken.register((_) {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
    }, null);
    try {
      await Future.any([
        releaseInProgress.then((_) => released = true),
        cancelled.future,
      ]);
    } finally {
      registration.dispose();
    }

    if (!released) {
      cancellationToken.throwIfCancellationRequested();
    }
  }

  /// Waits for the specified tasks to finish, giving up once the timeout
  /// elapses.
  ///
  /// The [BackgroundAgentRuntimeTask.completion] future never errors — task
  /// failures are captured into [BackgroundAgentRuntimeTask.error] — so
  /// awaiting it cannot throw (the C# unobserved-fault observer is inherent
  /// here).
  static Future<void> _waitForTasks(
    Iterable<BackgroundAgentRuntimeTask> tasks,
    Duration timeout,
    CancellationToken? cancellationToken,
  ) async {
    final pending = [
      for (final task in tasks)
        if (!task.isCompleted) task.completion,
    ];
    if (pending.isEmpty) {
      return;
    }

    final all = Future.wait(pending);

    final canBeCanceled = cancellationToken?.canBeCanceled ?? false;
    if (timeout == infiniteReleaseTimeout && !canBeCanceled) {
      await all;
      return;
    }

    var allDone = false;
    final interrupted = Completer<void>();
    Timer? delay;
    if (timeout != infiniteReleaseTimeout) {
      delay = Timer(timeout, () {
        if (!interrupted.isCompleted) {
          interrupted.complete();
        }
      });
    }
    final registration = canBeCanceled
        ? cancellationToken!.register((_) {
            if (!interrupted.isCompleted) {
              interrupted.complete();
            }
          }, null)
        : null;
    try {
      await Future.any([all.then((_) => allDone = true), interrupted.future]);
    } finally {
      delay?.cancel();
      registration?.dispose();
    }

    if (!allDone) {
      // The wait was abandoned; the remaining tasks are left to finish on
      // their own.
      cancellationToken?.throwIfCancellationRequested();
    }
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    final state = _sessionState.getOrInitializeState(context.session);
    final runtimeState = _runtimeSessionState.getOrInitializeState(
      context.session,
    );
    return Future.value(
      AIContext()
        ..instructions = _instructions
        ..tools = createTools(state, runtimeState, context.session),
    );
  }

  /// Validates the agent collection and builds a case-insensitive name
  /// dictionary.
  static Map<String, AIAgent> validateAndBuildAgentDictionary(
    Iterable<AIAgent> agents,
  ) {
    final dict = <String, AIAgent>{};
    final seenNames = <String>{};
    for (final agent in agents) {
      final agentName = agent.name;
      if (agentName == null || agentName.trim().isEmpty) {
        throw ArgumentError(
          'All background agents must have a non-empty Name.',
          'agents',
        );
      }

      final normalizedName = agentName.toLowerCase();
      if (!seenNames.add(normalizedName)) {
        throw ArgumentError(
          "Duplicate background agent name: '$agentName'. Agent names must be unique (case-insensitive).",
          'agents',
        );
      }

      dict[agentName] = agent;
    }
    if (dict.isEmpty) {
      throw ArgumentError(
        'At least one background agent must be provided.',
        'agents',
      );
    }
    return dict;
  }

  /// Builds the default text listing available background agents and their
  /// descriptions.
  static String buildDefaultAgentListText(Map<String, AIAgent> agents) {
    final sb = StringBuffer();
    sb.writeln('Available background agents:');
    for (final kvp in agents.entries) {
      sb.write('- ');
      sb.write(kvp.key);
      final description = kvp.value.description;
      if (description != null && description.trim().isNotEmpty) {
        sb.write(': ');
        sb.write(description);
      }
      sb.writeln();
    }
    return sb.toString();
  }

  /// Refreshes the status of in-flight tasks in the given state for the
  /// specified session.
  void tryRefreshTaskState(
    BackgroundAgentState state,
    BackgroundAgentRuntimeState runtimeState,
    AgentSession? session,
  ) {
    var changed = false;
    for (final task in state.tasks) {
      if (task.status != BackgroundTaskStatus.running) {
        continue;
      }

      final inFlight = runtimeState.inFlightTasks[task.id];
      if (inFlight == null) {
        // In-flight reference lost (e.g., after restart/deserialization).
        task.status = BackgroundTaskStatus.lost;
        changed = true;
        continue;
      }

      if (inFlight.isCompleted) {
        finalizeTask(task, inFlight, runtimeState);
        changed = true;
      }
    }

    if (changed) {
      _sessionState.saveState(session, state);
    }
  }

  /// Finalizes a task by extracting results from the completed Future and
  /// updating the [BackgroundTaskInfo].
  static void finalizeTask(
    BackgroundTaskInfo taskInfo,
    BackgroundAgentRuntimeTask completedTask,
    BackgroundAgentRuntimeState runtimeState,
  ) {
    final result = completedTask.result;
    final error = completedTask.error;
    if (result != null) {
      taskInfo.status = BackgroundTaskStatus.completed;
      taskInfo.resultText = result.text;
    } else if (error is OperationCanceledException) {
      taskInfo.status = BackgroundTaskStatus.failed;
      taskInfo.errorText = 'Task was canceled.';
    } else if (error != null) {
      taskInfo.status = BackgroundTaskStatus.failed;
      taskInfo.errorText = _getErrorMessage(error);
    }

    runtimeState.inFlightTasks.remove(taskInfo.id);
    _disposeTaskCancellation(runtimeState, taskInfo.id);
  }

  /// Removes and disposes the [CancellationTokenSource] tracked for the
  /// specified task, if any.
  static void _disposeTaskCancellation(
    BackgroundAgentRuntimeState runtimeState,
    int taskId,
  ) {
    final cts = runtimeState.taskCancellations.remove(taskId);
    cts?.dispose();
  }

  /// Starts a background run for the specified task, tracking the resulting
  /// future, the background agent session, and a [CancellationTokenSource]
  /// that allows the run to be cancelled when the session is released.
  ///
  /// Returns `true` if the run was started and tracked; `false` if the
  /// session was released before the run could be registered, in which case
  /// nothing is started. Re-checking here matters because the session may
  /// have been released while the caller awaited session creation — starting
  /// then would produce a task that is never tracked and therefore never
  /// cancelled.
  static bool _startTrackedRun(
    BackgroundAgentRuntimeState runtimeState,
    int taskId,
    AIAgent agent,
    String input,
    AgentSession subSession,
  ) {
    if (runtimeState.isReleased) {
      return false;
    }

    // Replace any cancellation source left over from a previous run of the
    // same task.
    _disposeTaskCancellation(runtimeState, taskId);

    final cts = CancellationTokenSource();
    runtimeState.taskCancellations[taskId] = cts;
    runtimeState.backgroundTaskSessions[taskId] = subSession;
    runtimeState.inFlightTasks[taskId] = _startTask(
      agent,
      input,
      subSession,
      cts.token,
    );
    return true;
  }

  List<AITool> createTools(
    BackgroundAgentState state,
    BackgroundAgentRuntimeState runtimeState,
    AgentSession? session,
  ) {
    return [
      AIFunctionFactory.create(
        name: 'BackgroundAgents_StartTask',
        description:
            'Start a background task on a named background agent. Returns a confirmation message containing the task ID.',
        parametersSchema: _objectSchema({
          'agentName':
              'The name of the background agent to delegate the task to.',
          'input': 'The request to pass to the background agent.',
          'description':
              'A description of the task used to identify the task later.',
        }),
        callback: (arguments, {cancellationToken}) async {
          if (runtimeState.isReleased) {
            return _releasedRuntimeStartError;
          }

          final agentName = _getRequiredString(arguments, 'agentName');
          final input = _getRequiredString(arguments, 'input');
          final description = _getRequiredString(arguments, 'description');

          final agent = _findAgent(agentName);
          if (agent == null) {
            return "Error: No background agent found with name '$agentName'. Available agents: ${_agents.keys.join(', ')}";
          }

          final taskId = state.nextTaskId++;
          final taskInfo = BackgroundTaskInfo()
            ..id = taskId
            ..agentName = agentName
            ..description = description
            ..status = BackgroundTaskStatus.running;
          state.tasks.add(taskInfo);

          // Create a dedicated session for this background task so it can be
          // continued later.
          final bgSession = await agent.createSession(
            cancellationToken: cancellationToken,
          );

          if (!_startTrackedRun(
            runtimeState,
            taskId,
            agent,
            input,
            bgSession,
          )) {
            // The session was released while the background session was being
            // created.
            state.tasks.remove(taskInfo);
            _sessionState.saveState(session, state);
            return _releasedRuntimeStartError;
          }

          _sessionState.saveState(session, state);
          return "Background task $taskId started on agent '$agentName'.";
        },
      ),
      AIFunctionFactory.create(
        name: 'BackgroundAgents_WaitForFirstCompletion',
        description:
            'Wait until the first of the specified background tasks completes or the configured timeout expires. Provide one or more task IDs. Returns a status message containing the ID of the task that completed first. On timeout, the tasks remain running and this tool can be called again to continue waiting.',
        parametersSchema: _objectSchema({
          'taskIds': 'The task IDs to wait on.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final taskIds = _getIntList(arguments, 'taskIds');
          if (taskIds.isEmpty) {
            return 'Error: No task IDs provided.';
          }

          // Collect in-flight tasks matching the requested IDs (including
          // already-completed ones, since Future.any returns immediately for
          // completed futures).
          final waitableTasks = <({int id, BackgroundAgentRuntimeTask task})>[];
          for (final id in taskIds) {
            final inFlight = runtimeState.inFlightTasks[id];
            if (inFlight != null) {
              waitableTasks.add((id: id, task: inFlight));
            }
          }

          if (waitableTasks.isEmpty) {
            // Refresh state to catch any that completed.
            tryRefreshTaskState(state, runtimeState, session);
            _sessionState.saveState(session, state);

            // Check if any of the requested IDs are already complete.
            final alreadyComplete = _firstOrNull(
              state.tasks,
              (t) =>
                  taskIds.contains(t.id) &&
                  t.status != BackgroundTaskStatus.running,
            );
            if (alreadyComplete != null) {
              return 'Task ${alreadyComplete.id} is not running; current status: ${_statusName(alreadyComplete.status)}.';
            }

            return 'Error: None of the specified task IDs correspond to running tasks.';
          }

          // Wait for the first task to complete, but return control without
          // stopping the tasks if the timeout elapses.
          final completedId = await Future.any(
            waitableTasks.map((t) => t.task.completion.then<int?>((_) => t.id)),
          ).timeout(_waitTimeout, onTimeout: () => null);

          if (completedId == null) {
            return 'No background task completed within '
                '${_formatSeconds(_waitTimeout)} seconds. The tasks are still '
                'running; call this tool again if you wish to continue '
                'waiting.';
          }

          // Find which ID completed.
          final completedEntry = waitableTasks.firstWhere(
            (t) => t.id == completedId,
          );

          // Finalize the completed task.
          final taskInfo = _firstOrNull(
            state.tasks,
            (t) => t.id == completedEntry.id,
          );
          if (taskInfo != null) {
            finalizeTask(taskInfo, completedEntry.task, runtimeState);
            _sessionState.saveState(session, state);
          }

          return 'Task ${completedEntry.id} finished with status: ${taskInfo != null ? _statusName(taskInfo.status) : "Unknown"}.';
        },
      ),
      AIFunctionFactory.create(
        name: 'BackgroundAgents_GetTaskResults',
        description:
            'Get the text output of a background task by its ID. Returns the result text if complete, or status information if still running or failed.',
        parametersSchema: _objectSchema({
          'taskId': 'The task ID to retrieve results for.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final taskId = _getRequiredInt(arguments, 'taskId');

          tryRefreshTaskState(state, runtimeState, session);

          final taskInfo = _firstOrNull(state.tasks, (t) => t.id == taskId);
          if (taskInfo == null) {
            return 'Error: No task found with ID $taskId.';
          }

          return switch (taskInfo.status) {
            BackgroundTaskStatus.completed =>
              taskInfo.resultText ?? '(no output)',
            BackgroundTaskStatus.failed =>
              'Task failed: ${taskInfo.errorText ?? "Unknown error"}',
            BackgroundTaskStatus.lost =>
              'Task state was lost (reference unavailable).',
            BackgroundTaskStatus.running => 'Task $taskId is still running.',
          };
        },
      ),
      AIFunctionFactory.create(
        name: 'BackgroundAgents_GetAllTasks',
        description:
            'List all background tasks with their IDs, statuses, agent names, and descriptions.',
        callback: (arguments, {cancellationToken}) async {
          tryRefreshTaskState(state, runtimeState, session);

          if (state.tasks.isEmpty) {
            return 'No tasks.';
          }

          final sb = StringBuffer();
          sb.writeln('Tasks:');
          for (final task in state.tasks) {
            sb.write('- Task ');
            sb.write(task.id);
            sb.write(' [');
            sb.write(_statusName(task.status));
            sb.write('] (');
            sb.write(task.agentName);
            sb.write('): ');
            sb.writeln(task.description);
          }

          return sb.toString();
        },
      ),
      AIFunctionFactory.create(
        name: 'BackgroundAgents_ContinueTask',
        description:
            "Send follow-up input to a completed or failed background task to resume its work. The background task's session is preserved, so the agent retains conversational context.",
        parametersSchema: _objectSchema({
          'taskId': 'The task ID to continue.',
          'text': 'The follow-up input to send to the background agent.',
        }),
        callback: (arguments, {cancellationToken}) async {
          if (runtimeState.isReleased) {
            return _releasedRuntimeContinueError;
          }

          final taskId = _getRequiredInt(arguments, 'taskId');
          final text = _getRequiredString(arguments, 'text');

          tryRefreshTaskState(state, runtimeState, session);

          final taskInfo = _firstOrNull(state.tasks, (t) => t.id == taskId);
          if (taskInfo == null) {
            return 'Error: No task found with ID $taskId.';
          }

          if (taskInfo.status == BackgroundTaskStatus.lost) {
            return 'Error: Task $taskId cannot be continued because its session was lost (e.g., after a session restore). Start a new task instead.';
          }

          if (taskInfo.status == BackgroundTaskStatus.running) {
            return 'Error: Task $taskId is still running. Wait for it to complete before continuing.';
          }

          final agent = _findAgent(taskInfo.agentName);
          if (agent == null) {
            return "Error: Agent '${taskInfo.agentName}' is no longer available.";
          }

          final bgSession = runtimeState.backgroundTaskSessions[taskId];
          if (bgSession == null) {
            return 'Error: Session for task $taskId is no longer available.';
          }

          // Reset task state and start a new run on the existing session.
          taskInfo.status = BackgroundTaskStatus.running;
          taskInfo.resultText = null;
          taskInfo.errorText = null;

          // Keep the same background task session for conversational continuity.
          if (!_startTrackedRun(runtimeState, taskId, agent, text, bgSession)) {
            taskInfo.status = BackgroundTaskStatus.failed;
            taskInfo.errorText = _releasedTaskCanceledMessage;
            _sessionState.saveState(session, state);
            return _releasedRuntimeContinueError;
          }

          _sessionState.saveState(session, state);
          return 'Task $taskId continued with new input.';
        },
      ),
      AIFunctionFactory.create(
        name: 'BackgroundAgents_ClearCompletedTask',
        description:
            'Remove a completed or failed background task and release its session to free memory. Use this after retrieving results when you no longer need to continue the task.',
        parametersSchema: _objectSchema({
          'taskId': 'The completed or failed task ID to clear.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final taskId = _getRequiredInt(arguments, 'taskId');

          tryRefreshTaskState(state, runtimeState, session);

          final taskInfo = _firstOrNull(state.tasks, (t) => t.id == taskId);
          if (taskInfo == null) {
            return 'Error: No task found with ID $taskId.';
          }

          if (taskInfo.status == BackgroundTaskStatus.running) {
            return 'Error: Task $taskId is still running. Wait for it to complete before clearing.';
          }

          // Remove the task from state.
          state.tasks.remove(taskInfo);

          // Clean up runtime references.
          runtimeState.inFlightTasks.remove(taskId);
          runtimeState.backgroundTaskSessions.remove(taskId);
          _disposeTaskCancellation(runtimeState, taskId);

          _sessionState.saveState(session, state);
          return 'Task $taskId cleared.';
        },
      ),
    ];
  }

  AIAgent? _findAgent(String agentName) {
    for (final entry in _agents.entries) {
      if (entry.key.toLowerCase() == agentName.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  static BackgroundAgentRuntimeTask _startTask(
    AIAgent agent,
    String input,
    AgentSession bgSession,
    CancellationToken? cancellationToken,
  ) {
    final currentRunContext = AIAgent.currentRunContext;
    try {
      return BackgroundAgentRuntimeTask(
        agent.run(
          bgSession,
          null,
          cancellationToken: cancellationToken,
          message: input,
        ),
      );
    } finally {
      AIAgent.currentRunContext = currentRunContext;
    }
  }

  static String _getRequiredString(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value is String) {
      return value;
    }
    throw ArgumentError.value(value, name, 'Expected a string argument.');
  }

  static int _getRequiredInt(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    throw ArgumentError.value(value, name, 'Expected an integer argument.');
  }

  static List<int> _getIntList(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value is List<int>) {
      return value;
    }
    if (value is Iterable) {
      return value.map((v) {
        if (v is int) {
          return v;
        }
        if (v is num) {
          return v.toInt();
        }
        throw ArgumentError.value(v, name, 'Expected integer values.');
      }).toList();
    }
    throw ArgumentError.value(value, name, 'Expected a list of integers.');
  }

  static T? _firstOrNull<T>(
    Iterable<T> source,
    bool Function(T value) predicate,
  ) {
    for (final value in source) {
      if (predicate(value)) {
        return value;
      }
    }
    return null;
  }

  /// Renders [duration] as a count of seconds without a trailing `.0`,
  /// matching the C# `TimeSpan.TotalSeconds:g` format used in the timeout
  /// message (300 seconds → `300`, 50 ms → `0.05`).
  static String _formatSeconds(Duration duration) {
    final seconds =
        duration.inMicroseconds / Duration.microsecondsPerSecond.toDouble();
    final text = seconds.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  static String _statusName(BackgroundTaskStatus status) {
    return switch (status) {
      BackgroundTaskStatus.running => 'Running',
      BackgroundTaskStatus.completed => 'Completed',
      BackgroundTaskStatus.failed => 'Failed',
      BackgroundTaskStatus.lost => 'Lost',
    };
  }

  static String _getErrorMessage(Object error) {
    if (error is SystemException && error.message != null) {
      return error.message!;
    }
    return error.toString();
  }

  static Map<String, dynamic> _objectSchema(Map<String, String> properties) {
    return {
      'type': 'object',
      'properties': {
        for (final entry in properties.entries)
          entry.key: {'description': entry.value},
      },
      'required': properties.keys.toList(),
    };
  }
}
