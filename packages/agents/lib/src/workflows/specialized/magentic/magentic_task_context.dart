import 'package:extensions/ai.dart';

import '../../../abstractions/ai_agent.dart';
import '../../magentic_progress_ledger.dart';
import 'chat_message_extensions.dart';

/// Limits that bound a Magentic task run.
class TaskLimits {
  /// Creates task limits.
  const TaskLimits({
    this.maxStallCount = defaultMaxStallCount,
    this.maxRoundCount,
    this.maxResetCount,
    this.maxProgressLedgerRetryCount = defaultMaxProgressLedgerRetryCount,
  });

  /// Default number of consecutive stalls tolerated before replanning.
  static const int defaultMaxStallCount = 3;

  /// Default number of progress-ledger parse retries.
  static const int defaultMaxProgressLedgerRetryCount = 3;

  /// Maximum consecutive stalls before a replan is triggered.
  final int maxStallCount;

  /// Maximum coordination rounds, or `null` for unlimited.
  final int? maxRoundCount;

  /// Maximum resets, or `null` for unlimited.
  final int? maxResetCount;

  /// Maximum progress-ledger parse retries.
  final int maxProgressLedgerRetryCount;
}

/// The current facts and plan produced by the manager.
class TaskLedger {
  /// Creates a task ledger.
  const TaskLedger(this.currentFacts, this.currentPlan);

  /// The current fact sheet.
  final ChatMessage currentFacts;

  /// The current plan.
  final ChatMessage currentPlan;
}

/// Mutable counters tracking progress through a Magentic task.
class TaskCounters {
  /// Creates task counters.
  TaskCounters({this.roundCount = 0, this.stallCount = 0, this.resetCount = 0});

  /// Number of coordination rounds executed.
  int roundCount;

  /// Number of consecutive stalls detected.
  int stallCount;

  /// Number of resets performed.
  int resetCount;
}

/// A serializable snapshot of a [MagenticTaskContext].
class MagenticTaskState {
  /// Creates a task state snapshot.
  const MagenticTaskState({
    required this.taskDefinition,
    required this.chatHistory,
    required this.taskLedger,
    required this.progressLedgerState,
    required this.counters,
    required this.terminated,
    required this.emitUpdateEvents,
  });

  /// The original task definition messages.
  final List<ChatMessage> taskDefinition;

  /// The manager-visible chat history.
  final List<ChatMessage> chatHistory;

  /// The current task ledger, if any.
  final TaskLedger? taskLedger;

  /// The captured progress-ledger answer set, if any.
  final Map<String, Object?>? progressLedgerState;

  /// The task counters.
  final TaskCounters counters;

  /// Whether the task has terminated.
  final bool terminated;

  /// Whether agent update events should be emitted.
  final bool? emitUpdateEvents;
}

/// Holds the working state for a single Magentic task run.
class MagenticTaskContext {
  /// Creates a task context for a new task.
  MagenticTaskContext(
    this._taskDefinition,
    List<AIAgent> team,
    this.taskLimits,
    this.emitUpdateEvents, {
    Iterable<ProgressLedgerSlot> additionalProgressQuestions = const [],
  }) : task = _taskDefinition.getText(),
       teamDescription = getTeamDescription(team),
       progressLedger = MagenticProgressLedger(
         getTeamNames(team),
         additionalQuestions: additionalProgressQuestions,
       );

  /// Restores a task context from a captured [state].
  factory MagenticTaskContext.fromState(
    MagenticTaskState state,
    List<AIAgent> team,
    TaskLimits limits, {
    Iterable<ProgressLedgerSlot> additionalProgressQuestions = const [],
  }) {
    final context = MagenticTaskContext(
      state.taskDefinition,
      team,
      limits,
      state.emitUpdateEvents,
      additionalProgressQuestions: additionalProgressQuestions,
    );
    context.taskLedger = state.taskLedger;
    context.taskCounters = state.counters;
    context.chatHistory = List<ChatMessage>.of(state.chatHistory);
    context.isTerminated = state.terminated;

    final ledgerState = state.progressLedgerState;
    if (ledgerState != null &&
        !context.progressLedger.tryUpdateState(ledgerState)) {
      throw StateError('Could not load progress ledger state value');
    }
    return context;
  }

  final List<ChatMessage> _taskDefinition;

  /// The rendered task text.
  final String task;

  /// A bullet description of the team.
  final String teamDescription;

  /// The task limits.
  final TaskLimits taskLimits;

  /// Whether agent update events should be emitted.
  final bool? emitUpdateEvents;

  /// The progress ledger for this task.
  final MagenticProgressLedger progressLedger;

  /// The manager-visible chat history.
  List<ChatMessage> chatHistory = <ChatMessage>[];

  /// The current task ledger, if any.
  TaskLedger? taskLedger;

  /// The task counters.
  TaskCounters taskCounters = TaskCounters();

  /// Whether the task has terminated.
  bool isTerminated = false;

  /// Whether the consecutive stall count has exceeded the limit.
  bool get isStalled => taskCounters.stallCount > taskLimits.maxStallCount;

  /// Returns whether the round and/or reset limits have been hit.
  (bool hitRoundLimit, bool hitResetLimit) checkLimits() => (
    taskLimits.maxRoundCount != null &&
        taskLimits.maxRoundCount! <= taskCounters.roundCount,
    taskLimits.maxResetCount != null &&
        taskLimits.maxResetCount! <= taskCounters.resetCount,
  );

  /// Renders a bullet description of [team].
  static String getTeamDescription(Iterable<AIAgent> team) =>
      team.map((agent) => '- ${agent.name}: ${agent.description}').join('\n');

  /// Renders a comma-separated list of [team] names.
  static String getTeamNames(Iterable<AIAgent> team) =>
      team.map((agent) => agent.name).join(', ');

  /// Captures the current state for checkpointing.
  MagenticTaskState exportState() => MagenticTaskState(
    taskDefinition: _taskDefinition,
    chatHistory: chatHistory,
    taskLedger: taskLedger,
    progressLedgerState: progressLedger.state,
    counters: taskCounters,
    terminated: isTerminated,
    emitUpdateEvents: emitUpdateEvents,
  );

  /// Clears the working chat history and bumps the reset counter.
  void reset() {
    chatHistory.clear();
    taskCounters.resetCount++;
    taskCounters.stallCount = 0;
  }
}
