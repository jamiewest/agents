import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../../../abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import 'background_agent_runtime_state.dart';
import 'background_agent_state.dart';
import 'background_agents_provider_options.dart';
import 'background_task_info.dart';
import 'background_task_status.dart';

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
/// * `BackgroundAgents_WaitForFirstCompletion` — Block until the first of the
///   specified tasks completes. Returns the completed task's ID.
/// * `BackgroundAgents_GetTaskResults` — Retrieve the text output of a
///   completed background task.
/// * `BackgroundAgents_GetAllTasks` — List all background tasks with their
///   IDs, statuses, descriptions, and agent names.
/// * `BackgroundAgents_ContinueTask` — Send follow-up input to a completed
///   background task's session to resume work.
/// * `BackgroundAgents_ClearCompletedTask` — Remove a completed background
///   task and release its session to free memory.
class BackgroundAgentsProvider extends AIContextProvider {
  /// Creates a [BackgroundAgentsProvider] with the given [agents] and optional
  /// [options].
  BackgroundAgentsProvider(
    Iterable<AIAgent> agents, {
    BackgroundAgentsProviderOptions? options,
  }) : _agents = validateAndBuildAgentDictionary(agents) {
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
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
    _runtimeSessionState = ProviderSessionState<BackgroundAgentRuntimeState>(
      (_) => BackgroundAgentRuntimeState(),
      '${runtimeType}_Runtime',
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
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

  final Map<String, AIAgent> _agents;

  late final ProviderSessionState<BackgroundAgentState> _sessionState;

  late final ProviderSessionState<BackgroundAgentRuntimeState>
  _runtimeSessionState;

  late final String _instructions;

  List<String>? _stateKeys;

  @override
  List<String> get stateKeys {
    return _stateKeys ??= [
      _sessionState.stateKey,
      _runtimeSessionState.stateKey,
    ];
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

          // Dart Futures start when created. Keeping this explicit mirrors the
          // C# Task.Run boundary while preserving the parent run context value.
          runtimeState.inFlightTasks[taskId] = _startTask(
            agent,
            input,
            bgSession,
            cancellationToken,
          );
          runtimeState.backgroundTaskSessions[taskId] = bgSession;

          _sessionState.saveState(session, state);
          return "Background task $taskId started on agent '$agentName'.";
        },
      ),
      AIFunctionFactory.create(
        name: 'BackgroundAgents_WaitForFirstCompletion',
        description:
            'Block until the first of the specified background tasks completes. Provide one or more task IDs. Returns a status message containing the ID of the task that completed first.',
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

          // Wait for the first one to complete.
          final completedId = await Future.any(
            waitableTasks.map((t) => t.task.completion.then((_) => t.id)),
          );

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
          runtimeState.inFlightTasks[taskId] = _startTask(
            agent,
            text,
            bgSession,
            cancellationToken,
          );

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
