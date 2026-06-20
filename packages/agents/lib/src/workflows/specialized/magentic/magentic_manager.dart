import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_response.dart';
import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../workflow_context.dart';
import '../../workflow_warning_event.dart';
import 'chat_message_extensions.dart';
import 'magentic_task_context.dart';
import 'prompt_templates.dart';

/// Drives the manager [AIAgent] that plans, tracks progress, and concludes a
/// Magentic task.
class MagenticManager {
  /// Creates a manager around [managerAgent].
  MagenticManager(this.managerAgent);

  /// The manager agent.
  final AIAgent managerAgent;

  static final Random _random = Random();

  /// Updates (or creates) the task plan, returning the new [TaskLedger].
  Future<TaskLedger> updatePlan(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    // When a ledger already exists we update facts; otherwise we build them.
    final isReplan = taskContext.taskLedger != null;

    final localSession = await managerAgent.createSession(
      cancellationToken: cancellationToken,
    );

    final factsRequest = ChatMessage.fromText(
      ChatRole.user,
      isReplan
          ? taskContext.toTaskLedgerFactsUpdatePrompt()
          : taskContext.toTaskLedgerFactsPrompt(),
    );
    final updatedFacts = await _invokeAgent(
      [...taskContext.chatHistory, factsRequest],
      context,
      cancellationToken,
      session: localSession,
    );

    final planRequest = ChatMessage.fromText(
      ChatRole.user,
      isReplan
          ? taskContext.toTaskLedgerPlanUpdatePrompt()
          : taskContext.toTaskLedgerPlanPrompt(),
    );
    // The session carries the conversation context, so the history, facts
    // request, and updated facts are not re-sent here.
    final updatedPlan = await _invokeAgent(
      [planRequest],
      context,
      cancellationToken,
      session: localSession,
    );

    taskContext.chatHistory.addAll([
      factsRequest,
      updatedFacts,
      planRequest,
      updatedPlan,
    ]);

    return TaskLedger(updatedFacts, updatedPlan);
  }

  /// Refreshes the progress ledger, retrying on JSON parse failures.
  Future<void> updateProgressLedger(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final progressRequest = ChatMessage.fromText(
      ChatRole.user,
      taskContext.toProgressLedgerPrompt(),
    );

    Object? lastError;
    StackTrace? lastStackTrace;
    final maxRetryCount = taskContext.taskLimits.maxProgressLedgerRetryCount;
    for (var attempts = 0; attempts < maxRetryCount; attempts++) {
      final progressUpdateMessage = await _invokeAgent(
        [...taskContext.chatHistory, progressRequest],
        context,
        cancellationToken,
      );

      try {
        lastError = null;
        lastStackTrace = null;
        final stateUpdateJson = progressUpdateMessage.extractJson();
        if (!taskContext.progressLedger.tryUpdateState(stateUpdateJson)) {
          throw StateError(
            'Could not answer progress ledger questions with provided JSON.',
          );
        }
        break;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        await _warn(
          context,
          'Progress ledger JSON parse failed '
          '(attempt $attempts/$maxRetryCount): $error',
          cancellationToken,
        );
        await Future<void>.delayed(Duration(milliseconds: 250 * attempts));
      }
    }

    if (lastError != null) {
      Error.throwWithStackTrace(
        lastError,
        lastStackTrace ?? StackTrace.current,
      );
    }
  }

  /// Produces the final answer message that concludes the task.
  Future<ChatMessage> prepareFinalAnswer(
    MagenticTaskContext taskContext,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    final finalAnswerRequest = ChatMessage.fromText(
      ChatRole.user,
      taskContext.toFinalAnswerPrompt(),
    );
    final finalAnswer = await _invokeAgent(
      [...taskContext.chatHistory, finalAnswerRequest],
      context,
      cancellationToken,
    );

    return ChatMessage(
      role: ChatRole.assistant,
      contents: [TextContent(finalAnswer.text)],
      authorName: finalAnswer.authorName ?? 'MagenticManager',
      messageId: finalAnswer.messageId ?? _newMessageId(),
      createdAt: finalAnswer.createdAt ?? DateTime.now().toUtc(),
      rawRepresentation: finalAnswer.rawRepresentation,
    );
  }

  Future<ChatMessage> _invokeAgent(
    Iterable<ChatMessage> messages,
    WorkflowContext context,
    CancellationToken cancellationToken, {
    AgentSession? session,
  }) async {
    final response = await managerAgent.run(
      session,
      null,
      cancellationToken: cancellationToken,
      messages: messages,
    );
    return _checkResponse(response, context, cancellationToken);
  }

  Future<ChatMessage> _checkResponse(
    AgentResponse response,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async {
    if (response.messages.isEmpty) {
      throw StateError('Planner Agent did not return any messages.');
    }
    if (response.messages.length > 1) {
      await _warn(
        context,
        'Planner Agent returned multiple messages; using the last one.',
        cancellationToken,
      );
    }
    return response.messages.last;
  }

  Future<void> _warn(
    WorkflowContext context,
    String message,
    CancellationToken cancellationToken,
  ) => context.yieldOutput(
    WorkflowWarningEvent(message),
    cancellationToken: cancellationToken,
  );

  static String _newMessageId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
