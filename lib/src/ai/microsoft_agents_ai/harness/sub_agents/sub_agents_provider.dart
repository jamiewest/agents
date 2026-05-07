import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import 'sub_agent_runtime_state.dart';
import 'sub_agent_state.dart';
import 'sub_agents_provider_options.dart';
import 'sub_task_info.dart';
import 'sub_task_status.dart';

/// An [AIContextProvider] that enables an agent to delegate work to
/// sub-agents asynchronously.
///
/// Remarks: The [SubAgentsProvider] allows a parent agent to start sub-tasks
/// on child agents, wait for their completion, and retrieve results. Each
/// sub-task runs in its own session and executes concurrently. This provider
/// exposes the following tools to the agent: `SubAgents_StartTask` — Start a
/// sub-task on a named agent with text input. Returns the task ID.
/// `SubAgents_WaitForFirstCompletion` — Block until the first of the
/// specified tasks completes. Returns the completed task's ID.
/// `SubAgents_GetTaskResults` — Retrieve the text output of a completed
/// sub-task. `SubAgents_GetAllTasks` — List all sub-tasks with their IDs,
/// statuses, descriptions, and agent names. `SubAgents_ContinueTask` — Send
/// follow-up input to a completed sub-task's session to resume work.
/// `SubAgents_ClearCompletedTask` — Remove a completed sub-task and release
/// its session to free memory.
class SubAgentsProvider extends AIContextProvider {
  /// Initializes a new instance of the [SubAgentsProvider] class.
  ///
  /// [agents] The collection of sub-agents available for delegation.
  ///
  /// [options] Optional settings controlling the provider behavior.
  SubAgentsProvider(
    Iterable<AIAgent> agents, {
    SubAgentsProviderOptions? options,
  }) : _agents = validateAndBuildAgentDictionary(agents) {
    final baseInstructions = options?.instructions ?? defaultInstructions;
    final agentListBuilder = options?.agentListBuilder;
    final agentListText = agentListBuilder != null
        ? agentListBuilder(_agents)
        : buildDefaultAgentListText(_agents);
    _instructions = baseInstructions.replaceAll('{sub_agents}', agentListText);
    _sessionState = ProviderSessionState<SubAgentState>(
      (_) => SubAgentState(),
      runtimeType.toString(),
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
    _runtimeSessionState = ProviderSessionState<SubAgentRuntimeState>(
      (_) => SubAgentRuntimeState(),
      '${runtimeType}_Runtime',
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  static const String defaultInstructions = '''
## SubAgents
You have access to sub-agents that can perform work on your behalf.

- Use the `SubAgents_*` list of tools to start tasks on sub agents and check their results.
- Creating a sub task does not block, and sub-tasks run concurrently.
- Important: Always wait for outstanding tasks to finish before you finish processing.
- Important: After retrieving results from a completed task, clear it with SubAgents_ClearCompletedTask to free memory, unless you plan to continue it with SubAgents_ContinueTask.

{sub_agents}
''';

  final Map<String, AIAgent> _agents;

  late final ProviderSessionState<SubAgentState> _sessionState;

  late final ProviderSessionState<SubAgentRuntimeState> _runtimeSessionState;

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
          'All sub-agents must have a non-empty Name.',
          'agents',
        );
      }

      final normalizedName = agentName.toLowerCase();
      if (!seenNames.add(normalizedName)) {
        throw ArgumentError(
          "Duplicate sub-agent name: '$agentName'. Agent names must be unique (case-insensitive).",
          'agents',
        );
      }

      dict[agentName] = agent;
    }
    if (dict.isEmpty) {
      throw ArgumentError('At least one sub-agent must be provided.', 'agents');
    }
    return dict;
  }

  /// Builds the default text listing available sub-agents and their
  /// descriptions.
  static String buildDefaultAgentListText(Map<String, AIAgent> agents) {
    final sb = StringBuffer();
    sb.writeln('Available sub-agents:');
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
    SubAgentState state,
    SubAgentRuntimeState runtimeState,
    AgentSession? session,
  ) {
    var changed = false;
    for (final task in state.tasks) {
      if (task.status != SubTaskStatus.running) {
        continue;
      }

      final inFlight = runtimeState.inFlightTasks[task.id];
      if (inFlight == null) {
        // In-flight reference lost (e.g., after restart/deserialization).
        task.status = SubTaskStatus.lost;
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
  /// updating the SubTaskInfo.
  static void finalizeTask(
    SubTaskInfo taskInfo,
    SubAgentRuntimeTask completedTask,
    SubAgentRuntimeState runtimeState,
  ) {
    final result = completedTask.result;
    final error = completedTask.error;
    if (result != null) {
      taskInfo.status = SubTaskStatus.completed;
      taskInfo.resultText = result.text;
    } else if (error is OperationCanceledException) {
      taskInfo.status = SubTaskStatus.failed;
      taskInfo.errorText = 'Task was canceled.';
    } else if (error != null) {
      taskInfo.status = SubTaskStatus.failed;
      taskInfo.errorText = _getErrorMessage(error);
    }

    runtimeState.inFlightTasks.remove(taskInfo.id);
  }

  List<AITool> createTools(
    SubAgentState state,
    SubAgentRuntimeState runtimeState,
    AgentSession? session,
  ) {
    return [
      AIFunctionFactory.create(
        name: 'SubAgents_StartTask',
        description:
            'Start a sub-task on a named sub-agent. Returns a confirmation message containing the task ID.',
        parametersSchema: _objectSchema({
          'agentName': 'The name of the sub agent to delegate the task to.',
          'input': 'The request to pass to the sub agent.',
          'description':
              'A description of the task used to identify the task later.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final agentName = _getRequiredString(arguments, 'agentName');
          final input = _getRequiredString(arguments, 'input');
          final description = _getRequiredString(arguments, 'description');

          final agent = _findAgent(agentName);
          if (agent == null) {
            return "Error: No sub-agent found with name '$agentName'. Available agents: ${_agents.keys.join(', ')}";
          }

          final taskId = state.nextTaskId++;
          final taskInfo = SubTaskInfo()
            ..id = taskId
            ..agentName = agentName
            ..description = description
            ..status = SubTaskStatus.running;
          state.tasks.add(taskInfo);

          // Create a dedicated session for this sub-task so it can be
          // continued later.
          final subSession = await agent.createSession(
            cancellationToken: cancellationToken,
          );

          // Dart Futures start when created. Keeping this explicit mirrors the
          // C# Task.Run boundary while preserving the parent run context value.
          runtimeState.inFlightTasks[taskId] = _startTask(
            agent,
            input,
            subSession,
            cancellationToken,
          );
          runtimeState.subTaskSessions[taskId] = subSession;

          _sessionState.saveState(session, state);
          return "Sub-task $taskId started on agent '$agentName'.";
        },
      ),
      AIFunctionFactory.create(
        name: 'SubAgents_WaitForFirstCompletion',
        description:
            'Block until the first of the specified sub-tasks completes. Provide one or more task IDs. Returns a status message containing the ID of the task that completed first.',
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
          final waitableTasks = <({int id, SubAgentRuntimeTask task})>[];
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
                  taskIds.contains(t.id) && t.status != SubTaskStatus.running,
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
        name: 'SubAgents_GetTaskResults',
        description:
            'Get the text output of a sub-task by its ID. Returns the result text if complete, or status information if still running or failed.',
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
            SubTaskStatus.completed => taskInfo.resultText ?? '(no output)',
            SubTaskStatus.failed =>
              'Task failed: ${taskInfo.errorText ?? "Unknown error"}',
            SubTaskStatus.lost =>
              'Task state was lost (reference unavailable).',
            SubTaskStatus.running => 'Task $taskId is still running.',
          };
        },
      ),
      AIFunctionFactory.create(
        name: 'SubAgents_GetAllTasks',
        description:
            'List all sub-tasks with their IDs, statuses, agent names, and descriptions.',
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
        name: 'SubAgents_ContinueTask',
        description:
            "Send follow-up input to a completed or failed sub-task to resume its work. The sub-task's session is preserved, so the agent retains conversational context.",
        parametersSchema: _objectSchema({
          'taskId': 'The task ID to continue.',
          'text': 'The follow-up input to send to the sub-agent.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final taskId = _getRequiredInt(arguments, 'taskId');
          final text = _getRequiredString(arguments, 'text');

          tryRefreshTaskState(state, runtimeState, session);

          final taskInfo = _firstOrNull(state.tasks, (t) => t.id == taskId);
          if (taskInfo == null) {
            return 'Error: No task found with ID $taskId.';
          }

          if (taskInfo.status == SubTaskStatus.lost) {
            return 'Error: Task $taskId cannot be continued because its session was lost (e.g., after a session restore). Start a new task instead.';
          }

          if (taskInfo.status == SubTaskStatus.running) {
            return 'Error: Task $taskId is still running. Wait for it to complete before continuing.';
          }

          final agent = _findAgent(taskInfo.agentName);
          if (agent == null) {
            return "Error: Agent '${taskInfo.agentName}' is no longer available.";
          }

          final subSession = runtimeState.subTaskSessions[taskId];
          if (subSession == null) {
            return 'Error: Session for task $taskId is no longer available.';
          }

          // Reset task state and start a new run on the existing session.
          taskInfo.status = SubTaskStatus.running;
          taskInfo.resultText = null;
          taskInfo.errorText = null;

          // Keep the same sub-task session for conversational continuity.
          runtimeState.inFlightTasks[taskId] = _startTask(
            agent,
            text,
            subSession,
            cancellationToken,
          );

          _sessionState.saveState(session, state);
          return 'Task $taskId continued with new input.';
        },
      ),
      AIFunctionFactory.create(
        name: 'SubAgents_ClearCompletedTask',
        description:
            'Remove a completed or failed sub-task and release its session to free memory. Use this after retrieving results when you no longer need to continue the task.',
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

          if (taskInfo.status == SubTaskStatus.running) {
            return 'Error: Task $taskId is still running. Wait for it to complete before clearing.';
          }

          // Remove the task from state.
          state.tasks.remove(taskInfo);

          // Clean up runtime references.
          runtimeState.inFlightTasks.remove(taskId);
          runtimeState.subTaskSessions.remove(taskId);

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

  static SubAgentRuntimeTask _startTask(
    AIAgent agent,
    String input,
    AgentSession subSession,
    CancellationToken? cancellationToken,
  ) {
    final currentRunContext = AIAgent.currentRunContext;
    try {
      return SubAgentRuntimeTask(
        agent.run(
          subSession,
          null,
          cancellationToken ?? CancellationToken.none,
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

  static String _statusName(SubTaskStatus status) {
    return switch (status) {
      SubTaskStatus.running => 'Running',
      SubTaskStatus.completed => 'Completed',
      SubTaskStatus.failed => 'Failed',
      SubTaskStatus.lost => 'Lost',
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
