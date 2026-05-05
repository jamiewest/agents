import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import '../../open_telemetry_consts.dart';
import 'sub_agent_runtime_state.dart';
import 'sub_agent_state.dart';
import 'sub_agents_provider_options.dart';
import 'sub_task_info.dart';
import 'sub_task_status.dart';
import '../../../../map_extensions.dart';

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
    Iterable<AIAgent> agents,
    {SubAgentsProviderOptions? options = null, },
  ) : _agents = agents {
    _ = agents;
    this._agents = validateAndBuildAgentDictionary(agents);
    var baseInstructions = options?.instructions ?? DefaultInstructions;
    var agentListText = options?.agentListBuilder != null
            ? options.agentListBuilder(this._agents)
            : buildDefaultAgentListText(this._agents);
    this._instructions = baseInstructions.replaceAll("{sub_agents}", agentListText);
    this._sessionState = ProviderSessionState<SubAgentState>(
            (_) => subAgentState(),
            this.runtimeType.toString(),
            AgentJsonUtilities.defaultOptions);
    this._runtimeSessionState = ProviderSessionState<SubAgentRuntimeState>(
            (_) => subAgentRuntimeState(),
            this.runtimeType.toString() + "_Runtime",
            AgentJsonUtilities.defaultOptions);
  }

  final Map<String, AIAgent> _agents;

  late final ProviderSessionState<SubAgentState> _sessionState;

  late final ProviderSessionState<SubAgentRuntimeState> _runtimeSessionState;

  late final String _instructions;

  List<String>? _stateKeys;

  List<String> get stateKeys {
    return this._stateKeys ??= [this._sessionState.stateKey, this._runtimeSessionState.stateKey];
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) {
    var state = this._sessionState.getOrInitializeState(context.session);
    var runtimeState = this._runtimeSessionState.getOrInitializeState(context.session);
    return Future<AIContext>(AIContext());
  }

  /// Validates the agent collection and builds a case-insensitive name
  /// dictionary.
  static Map<String, AIAgent> validateAndBuildAgentDictionary(Iterable<AIAgent> agents) {
    var dict = new Dictionary<String, AIAgent>();
    for (final agent in agents) {
      if ((agent.name == null || agent.name.trim().isEmpty)) {
        throw ArgumentError("All sub-agents must have a non-empty Name.", 'agents');
      }
      if (dict.containsKey(agent.name)) {
        throw ArgumentError(
          "Duplicate sub-agent name: ${agent.name}. Agent names must be unique (case-insensitive).",
          'agents',
        );
      }
      dict[agent.name] = agent;
    }
    if (dict.length == 0) {
      throw ArgumentError("At least one sub-agent must be provided.", 'agents');
    }
    return dict;
  }

  /// Builds the default text listing available sub-agents and their
  /// descriptions.
  static String buildDefaultAgentListText(Map<String, AIAgent> agents) {
    var sb = StringBuffer();
    sb.writeln("Available sub-agents:");
    for (final kvp in agents) {
      sb.write("- ").write(kvp.key);
      if (!(kvp.value.description == null || kvp.value.description.trim().isEmpty)) {
        sb.write(": ").write(kvp.value.description);
      }
      sb.writeln();
    }
    return sb.toString();
  }

  /// Refreshes the status of in-flight tasks in the given state for the
  /// specified session.
  void tryRefreshFutureState(
    SubAgentState state,
    SubAgentRuntimeState runtimeState,
    AgentSession? session,
  ) {
    var changed = false;
    for (final task in state.tasks) {
      if (task.status != SubTaskStatus.running) {
        continue;
      }
      Task<AgentResponse>? inFlight;
      if (!runtimeState.inFlightTasks.containsKey(task.id)) {
        // In-flight reference lost (e.g., after restart/deserialization).
                task.status = SubTaskStatus.lost;
        changed = true;
        continue;
      }
      if (inFlight.isCompleted) {
        finalizeFuture(task, inFlight, runtimeState);
        changed = true;
      }
    }
    if (changed) {
      this._sessionState.saveState(session, state);
    }
  }

  /// Finalizes a task by extracting results from the completed Task and
  /// updating the SubTaskInfo.
  static void finalizeFuture(
    SubTaskInfo taskInfo,
    Future<AgentResponse> completedTask,
    SubAgentRuntimeState runtimeState,
  ) {
    if (completedTask.status == TaskStatus.ranToCompletion) {
      taskInfo.status = SubTaskStatus.completed;
      #pragma warning disable VSTHRD002 // Avoid problematic synchronous waits — task is already completed
            taskInfo.resultText = completedTask.result.text;
    } else if (completedTask.isFaulted) {
      taskInfo.status = SubTaskStatus.failed;
      taskInfo.errorText = completedTask.exception?.innerException?.message ?? completedTask.exception?.message ?? "Unknown error";
    } else if (completedTask.isCanceled) {
      taskInfo.status = SubTaskStatus.failed;
      taskInfo.errorText = "Task was canceled.";
    }
    runtimeState.inFlightTasks.remove(taskInfo.id);
  }

  List<AITool> createTools(
    SubAgentState state,
    SubAgentRuntimeState runtimeState,
    AgentSession? session,
  ) {
    var serializerOptions = AgentJsonUtilities.defaultOptions;
    return [
            AIFunctionFactory.create(
                async (
                    [description("The name of the sub agent to delegate the task to.")] String agentName,
                    [description("The request to pass to the sub agent.")] String input,
                    [description("A description of the task used to identify the task later.")] String description) =>
                {
                    if (!this._agents.tryGetValue(agentName))
                    {
                        return "Error: No sub-agent found with name $agentName. Available agents: ${this._agents.keys.join(', ')}";
      }

                    int taskId = state.nextFutureId++;
                    var taskInfo = subFutureInfo();
                    state.tasks.add(taskInfo);

                    // Create a dedicated session for this sub-task so it can be continued later.
                    AgentSession subSession = await agent.createSessionAsync();

                    // Wrap in Task.run to fork the ExecutionContext. AIAgent.runAsync is a non-async
                    // method that synchronously sets the static AsyncLocal CurrentRunContext. Without
                    // this isolation, the sub-agent's RunAsync would overwrite the outer (calling)
                    // agent's CurrentRunContext, corrupting all subsequent tool invocations in the
                    // same FICC batch.
                    runtimeState.inFlightTasks[taskId] = Task.run(() => agent.runAsync(input, subSession));
                    runtimeState.subFutureSessions[taskId] = subSession;

                    this._sessionState.saveState(session, state);
                    return "Sub-task ${taskId} started on agent ${agentName}.";
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                async (List<int> taskIds) =>
                {
                    if (taskIds.length == 0)
                    {
                        return "Error: No task IDs provided.";
      }

                    // Collect in-flight tasks matching the requested iDs(including already-completed ones,
                    // since Task.whenAny returns immediately for completed tasks).
                    var waitableTasks = List<(int Id, Task<AgentResponse> Task)>();
                    foreach (int id in taskIds)
                    {
                        if (runtimeState.inFlightTasks.tryGetValue(id))
                        {
                            waitableTasks.add((id, inFlight));
        }
      }

                    if (waitableTasks.length == 0)
                    {
                        // Refresh state to catch any that completed.
                        this.tryRefreshFutureState(state, runtimeState, session);
                        this._sessionState.saveState(session, state);

                        // Check if any of the requested IDs are already complete.
                        SubTaskInfo? alreadyComplete = state.tasks.firstOrDefault((t) => taskIds.contains(t.id) && t.status != SubTaskStatus.running);
                        if (alreadyComplete != null)
                        {
                            return 'Task ${alreadyComplete.id} is! running; current status: ${alreadyComplete.status}.';
        }

                        return "Error: None of the specified task IDs correspond to running tasks.";
      }

                    // Wait for the first one to complete.
                    Task completedTask = await Task.whenAny(waitableTasks.map((t) => t.task));

                    // Find which ID completed.
                    var completedEntry = waitableTasks.first((t) => t.task == completedTask);

                    // Finalize the completed task.
                    SubTaskInfo? taskInfo = state.tasks.firstOrDefault((t) => t.id == completedEntry.id);
                    if (taskInfo != null)
                    {
                        finalizeFuture(taskInfo, completedEntry.task, runtimeState);
                        this._sessionState.saveState(session, state);
      }

                    return 'Task ${completedEntry.id} finished with status: ${taskInfo?.status.toString() ?? "Unknown"}.';
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                (int taskId) =>
                {
                    this.tryRefreshFutureState(state, runtimeState, session);

                    SubTaskInfo? taskInfo = state.tasks.firstOrDefault((t) => t.id == taskId);
                    if (taskInfo == null)
                    {
                        return 'Error: No task found with ID ${taskId}.';
      }

                    return taskInfo.status switch
                    {
                        SubTaskStatus.completed => taskInfo.resultText ?? "(no output)",
                        SubTaskStatus.failed => 'Task failed: ${taskInfo.errorText ?? "Unknown error"}',
                        SubTaskStatus.lost => "Task state was lost (reference unavailable).",
                        SubTaskStatus.running => 'Task ${taskId} is still running.',
                        (_) => 'Task ${taskId} has status: ${taskInfo.status}.',
                    };
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                () =>
                {
                    this.tryRefreshFutureState(state, runtimeState, session);

                    if (state.tasks.length == 0)
                    {
                        return "No tasks.";
      }

                    var sb = StringBuffer();
                    sb.writeln("Tasks:");
                    foreach (SubTaskInfo task in state.tasks)
                    {
                        sb.write("- Task ").write(task.id).write(" [").write(task.status).write("] (").write(task.agentName).write("): ").writeln(task.description);
      }

                    return sb.toString();
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                (int taskId, String text) =>
                {
                    this.tryRefreshFutureState(state, runtimeState, session);

                    SubTaskInfo? taskInfo = state.tasks.firstOrDefault((t) => t.id == taskId);
                    if (taskInfo == null)
                    {
                        return 'Error: No task found with ID ${taskId}.';
      }

                    if (taskInfo.status == SubTaskStatus.lost)
                    {
                        return 'Error: Task $taskId cannot be continued because its session was lost '
                          '(e.g., after a session restore). Start a new task instead.';
      }

                    if (taskInfo.status == SubTaskStatus.running)
                    {
                        return 'Error: Task ${taskId} is still running. Wait for it to complete before continuing.';
      }

                    if (!this._agents.tryGetValue(taskInfo.agentName))
                    {
                        return "Error: Agent ${taskInfo.agentName} is no longer available.";
      }

                    if (!runtimeState.subFutureSessions.tryGetValue(taskId))
                    {
                        return 'Error: Session for task ${taskId} is no longer available.';
      }

                    // Reset task state and start a new run on the existing session.
                    taskInfo.status = SubTaskStatus.running;
                    taskInfo.resultText = null;
                    taskInfo.errorText = null;

                    // Wrap in Task.run to isolate the executionContext(see StartSubTask comment).
                    runtimeState.inFlightTasks[taskId] = Task.run(() => agent.runAsync(text, subSession));

                    this._sessionState.saveState(session, state);
                    return 'Task ${taskId} continued with new input.';
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                (int taskId) =>
                {
                    this.tryRefreshFutureState(state, runtimeState, session);

                    SubTaskInfo? taskInfo = state.tasks.firstOrDefault((t) => t.id == taskId);
                    if (taskInfo == null)
                    {
                        return 'Error: No task found with ID ${taskId}.';
      }

                    if (taskInfo.status == SubTaskStatus.running)
                    {
                        return 'Error: Task ${taskId} is still running. Wait for it to complete before clearing.';
      }

                    // Remove the task from state.
                    state.tasks.remove(taskInfo);

                    // Clean up runtime references.
                    runtimeState.inFlightTasks.remove(taskId);
                    runtimeState.subFutureSessions.remove(taskId);

                    this._sessionState.saveState(session, state);
                    return 'Task ${taskId} cleared.';
                },
                AIFunctionFactoryOptions()),
        ];
  }
}
