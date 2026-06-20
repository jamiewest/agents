import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../chat_protocol.dart';
import '../../executor.dart';
import '../../magentic_plan_review_request.dart';
import '../../magentic_plan_review_response.dart';
import '../../magentic_progress_ledger.dart';
import '../../protocol_builder.dart';
import '../../request_port.dart';
import '../../resettable_executor.dart';
import '../../workflow_context.dart';
import '../../workflow_event.dart';
import '../../workflow_warning_event.dart';
import 'magentic_manager.dart';
import 'magentic_task_context.dart';
import 'prompt_templates.dart';

/// Base type for Magentic orchestration events.
///
/// The orchestrator emits these via [WorkflowContext.yieldOutput] (the only
/// event channel available to executors in this port), so consumers observe
/// them as the `data` of a workflow output event, interleaved with the final
/// answer. Distinguish them by type: a [MagenticOrchestratorEvent] is an
/// informational event, whereas a `List<ChatMessage>` payload is the result.
abstract class MagenticOrchestratorEvent extends WorkflowEvent {
  /// Creates a Magentic orchestrator event carrying [data].
  MagenticOrchestratorEvent(Object? data) : super(data: data);
}

/// Signals creation of the initial plan.
class MagenticPlanCreatedEvent extends MagenticOrchestratorEvent {
  /// Creates a plan-created event for [fullTaskLedger].
  MagenticPlanCreatedEvent(this.fullTaskLedger) : super(fullTaskLedger);

  /// A message containing the initial plan.
  final ChatMessage fullTaskLedger;
}

/// Signals creation of a new plan in response to a stall.
class MagenticReplannedEvent extends MagenticOrchestratorEvent {
  /// Creates a replanned event for [fullTaskLedger].
  MagenticReplannedEvent(this.fullTaskLedger) : super(fullTaskLedger);

  /// A message containing the new plan.
  final ChatMessage fullTaskLedger;
}

/// Signals an update to the progress ledger during a coordination round.
class MagenticProgressLedgerUpdatedEvent extends MagenticOrchestratorEvent {
  /// Creates a progress-ledger-updated event for [progressLedger].
  MagenticProgressLedgerUpdatedEvent(this.progressLedger)
    : super(progressLedger);

  /// The new state of the progress ledger.
  final MagenticProgressLedger progressLedger;
}

/// Centralized, re-entrant Magentic orchestrator.
///
/// On the first turn it builds a plan with the manager, optionally requests
/// human sign-off through [planReviewPort], then runs coordination rounds. Each
/// round refreshes the progress ledger, checks for completion or stalls, and
/// invokes the selected team agent inline. When sign-off is required the
/// orchestrator posts a plan-review request and returns; it resumes when a
/// [MagenticPlanReviewResponse] is delivered back to it.
class MagenticOrchestrator extends Executor<Object?, List<ChatMessage>?>
    implements ResettableExecutor {
  /// Creates a Magentic orchestrator.
  MagenticOrchestrator({
    required AIAgent managerAgent,
    required List<AIAgent> team,
    required this.limits,
    required this.requirePlanSignoff,
    required this.planReviewPort,
    String? id,
  }) : _manager = MagenticManager(managerAgent),
       team = List<AIAgent>.unmodifiable(team),
       super(id ?? defaultId);

  /// Default executor identifier.
  static const String defaultId = 'MagenticOrchestrator';

  final MagenticManager _manager;

  /// The participating team agents.
  final List<AIAgent> team;

  /// The task limits applied to the run.
  final TaskLimits limits;

  /// Whether human plan sign-off is required before execution.
  final bool requirePlanSignoff;

  /// The port used to request human plan review.
  ///
  /// The response type is nullable so the runtime can construct its
  /// pending-response placeholder before the human reply arrives.
  final RequestPort<MagenticPlanReviewRequest, MagenticPlanReviewResponse?>
  planReviewPort;

  final Map<String, AgentSession> _sessions = <String, AgentSession>{};
  MagenticTaskContext? _taskContext;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    ChatProtocol.configureInput(builder);
    builder
      ..acceptsMessage<MagenticPlanReviewResponse>()
      ..sendsMessage<List<ChatMessage>>()
      ..requests(planReviewPort);
  }

  @override
  Future<List<ChatMessage>?> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;

    if (message is MagenticPlanReviewResponse) {
      await _processPlanReview(message, context, token);
    } else {
      await _takeTurn(ChatProtocol.toChatMessages(message), context, token);
    }
    // Output flows exclusively through yieldOutput; returning null avoids
    // double-emitting at suspend points and avoids spurious downstream routing.
    return null;
  }

  Future<void> _takeTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final existing = _taskContext;
    if (existing?.isTerminated == true) {
      throw StateError(_terminatedMessage);
    }

    if (existing == null) {
      final taskContext = _taskContext = MagenticTaskContext(
        messages,
        team,
        limits,
        null,
      );
      await _updatePlanAndDelegate(taskContext, context, cancellationToken);
    } else {
      // Unreachable in normal inline flow: team replies are consumed inline
      // within the coordination loop, and human plan reviews re-enter through
      // _processPlanReview. This branch only fires if extra task messages are
      // delivered to an in-progress orchestrator.
      if (messages.isNotEmpty) {
        existing.chatHistory.addAll(messages);
      }
      await _runCoordinationRound(existing, context, cancellationToken);
    }
  }

  Future<void> _processPlanReview(
    MagenticPlanReviewResponse response,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final taskContext = _taskContext;
    if (taskContext == null || taskContext.taskLedger == null) {
      throw StateError('Magentic Orchestration was not initialized correctly.');
    }
    if (taskContext.isTerminated) {
      throw StateError(_terminatedMessage);
    }

    if (response.isApproved) {
      await _runCoordinationRound(taskContext, context, cancellationToken);
    } else {
      taskContext.chatHistory.addAll(response.review);
      await _updatePlanAndDelegate(taskContext, context, cancellationToken);
    }
  }

  Future<void> _updatePlanAndDelegate(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken, {
    bool replanAfterStall = false,
  }) async {
    final isReplan = taskContext.taskLedger != null;

    taskContext.taskLedger = await _manager.updatePlan(
      taskContext,
      context,
      cancellationToken,
    );

    final fullTaskLedgerMessage = ChatMessage.fromText(
      ChatRole.user,
      taskContext.toTaskLedgerFullPrompt(),
    );
    taskContext.chatHistory.add(fullTaskLedgerMessage);

    await context.yieldOutput(
      isReplan
          ? MagenticReplannedEvent(fullTaskLedgerMessage)
          : MagenticPlanCreatedEvent(fullTaskLedgerMessage),
      cancellationToken: cancellationToken,
    );

    if (requirePlanSignoff) {
      await _submitPlanReviewRequest(
        taskContext,
        context,
        cancellationToken,
        replanAfterStall: replanAfterStall,
      );
    } else {
      await _runCoordinationRound(taskContext, context, cancellationToken);
    }
  }

  Future<void> _submitPlanReviewRequest(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken, {
    bool replanAfterStall = false,
  }) async {
    final progressLedger = taskContext.progressLedger;
    final progress = progressLedger.isStarted ? progressLedger : null;
    final request = MagenticPlanReviewRequest(
      taskContext.taskLedger!.currentPlan,
      progress,
      replanAfterStall,
    );
    await context.sendRequest(
      planReviewPort,
      request,
      cancellationToken: cancellationToken,
    );
  }

  Future<void> _runCoordinationRound(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    // This loop runs every coordination round inline within a single
    // super-step, so it is the one place in the orchestrator that can spin
    // without yielding; honour cancellation explicitly at the top.
    while (true) {
      cancellationToken.throwIfCancellationRequested();

      final (hitRoundLimit, hitResetLimit) = taskContext.checkLimits();
      if (hitRoundLimit || hitResetLimit) {
        final limitType = hitRoundLimit ? 'round' : 'reset';
        await context.yieldOutput(<ChatMessage>[
          ChatMessage.fromText(
            ChatRole.assistant,
            'Task execution stopped due to hitting the maximum '
            '$limitType count limit.',
          ),
        ], cancellationToken: cancellationToken);
        taskContext.isTerminated = true;
        return;
      }

      taskContext.taskCounters.roundCount++;

      try {
        await _manager.updateProgressLedger(
          taskContext,
          context,
          cancellationToken,
        );
        await context.yieldOutput(
          MagenticProgressLedgerUpdatedEvent(
            taskContext.progressLedger.snapshot(),
          ),
          cancellationToken: cancellationToken,
        );
      } on OperationCanceledException {
        rethrow;
      } catch (error) {
        await _warn(
          context,
          'Magentic Orchestrator: Progress ledger creation failed, '
          'triggering reset: $error',
          cancellationToken,
        );
        await _resetAndReplan(taskContext, context, cancellationToken);
        return;
      }

      if (taskContext.progressLedger.isRequestSatisfied) {
        await _prepareFinalAnswer(taskContext, context, cancellationToken);
        return;
      }

      if (taskContext.progressLedger.isInLoop ||
          !taskContext.progressLedger.isProgressBeingMade) {
        taskContext.taskCounters.stallCount++;
      } else {
        taskContext.taskCounters.stallCount = max(
          0,
          taskContext.taskCounters.stallCount - 1,
        );
      }

      if (taskContext.isStalled) {
        await _resetAndReplan(taskContext, context, cancellationToken);
        return;
      }

      var nextSpeaker = taskContext.progressLedger.nextSpeaker;
      if (nextSpeaker.isEmpty) {
        await _warn(
          context,
          'Next speaker answer empty; selecting first participant as fallback',
          cancellationToken,
        );
        nextSpeaker = team.first.name ?? team.first.id;
      }

      final nextAgent = _agentNamed(nextSpeaker);
      if (nextAgent == null) {
        await _warn(
          context,
          'Invalid next speaker: $nextSpeaker',
          cancellationToken,
        );
        await _prepareFinalAnswer(taskContext, context, cancellationToken);
        return;
      }

      final instruction = taskContext.progressLedger.instructionOrQuestion;
      if (instruction.trim().isNotEmpty) {
        taskContext.chatHistory.add(
          ChatMessage.fromText(ChatRole.assistant, instruction),
        );
      }

      final reply = await _invokeTeamAgent(
        nextAgent,
        taskContext,
        cancellationToken,
      );
      taskContext.chatHistory.addAll(reply);
    }
  }

  Future<void> _resetAndReplan(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final wasStalled = taskContext.isStalled;
    taskContext.reset();
    // Dropping the team sessions is the inline equivalent of broadcasting a
    // reset signal to participant executors.
    _sessions.clear();
    await _updatePlanAndDelegate(
      taskContext,
      context,
      cancellationToken,
      replanAfterStall: wasStalled,
    );
  }

  Future<void> _prepareFinalAnswer(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final message = await _manager.prepareFinalAnswer(
      taskContext,
      context,
      cancellationToken,
    );
    await context.yieldOutput(<ChatMessage>[
      message,
    ], cancellationToken: cancellationToken);
    taskContext.isTerminated = true;
  }

  Future<List<ChatMessage>> _invokeTeamAgent(
    AIAgent agent,
    MagenticTaskContext taskContext,
    CancellationToken cancellationToken,
  ) async {
    final session = _sessions[agent.id] ??= await agent.createSession(
      cancellationToken: cancellationToken,
    );
    final messagesForAgent = _changeAssistantToUserForOtherParticipants(
      taskContext.chatHistory,
      agent.name ?? agent.id,
    );
    final response = await agent.run(
      session,
      null,
      cancellationToken: cancellationToken,
      messages: messagesForAgent,
    );
    return _normalizeAuthor(response.messages, agent).toList();
  }

  AIAgent? _agentNamed(String name) {
    for (final agent in team) {
      if (agent.name == name) {
        return agent;
      }
    }
    return null;
  }

  Future<void> _warn(
    WorkflowContext context,
    String message,
    CancellationToken cancellationToken,
  ) => context.yieldOutput(
    WorkflowWarningEvent(message),
    cancellationToken: cancellationToken,
  );

  @override
  Future<bool> reset() async {
    _sessions.clear();
    _taskContext = null;
    return true;
  }

  static const String _terminatedMessage =
      'This Magentic orchestration has already terminated. To process new '
      'messages, create a new workflow instance.';

  static Iterable<ChatMessage> _normalizeAuthor(
    Iterable<ChatMessage> messages,
    AIAgent agent,
  ) sync* {
    for (final message in messages) {
      if (message.authorName == null && message.role == ChatRole.assistant) {
        yield ChatMessage(
          role: message.role,
          contents: message.contents,
          authorName: agent.name ?? agent.id,
          createdAt: message.createdAt,
          messageId: message.messageId,
          rawRepresentation: message.rawRepresentation,
          additionalProperties: message.additionalProperties,
        );
      } else {
        yield message;
      }
    }
  }

  static List<ChatMessage> _changeAssistantToUserForOtherParticipants(
    Iterable<ChatMessage> messages,
    String targetAgentName,
  ) => [
    for (final message in messages)
      if (message.role == ChatRole.assistant &&
          message.authorName != targetAgentName &&
          message.contents.every(
            (content) =>
                content is TextContent ||
                content is DataContent ||
                content is UriContent ||
                content is UsageContent,
          ))
        ChatMessage(
          role: ChatRole.user,
          contents: message.contents,
          authorName: message.authorName,
          createdAt: message.createdAt,
          messageId: message.messageId,
          rawRepresentation: message.rawRepresentation,
          additionalProperties: message.additionalProperties,
        )
      else
        message,
  ];
}
