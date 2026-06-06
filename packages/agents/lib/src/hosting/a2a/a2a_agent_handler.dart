import 'dart:math';

import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

import '../../a2a/extensions/chat_message_extensions.dart';
import '../../abstractions/agent_response.dart';
import '../../abstractions/agent_run_options.dart';
import '../../abstractions/agent_session.dart';
import '../ai_host_agent.dart';
import 'a2a_run_decision_context.dart';
import 'agent_run_mode.dart';
import 'converters/message_converter.dart';

/// Bridges an [AIHostAgent] to the A2A (Agent2Agent) protocol.
///
/// Implements the A2A server [A2AAgentExecutor] seam: it runs the underlying
/// agent for incoming requests and publishes the results to the supplied
/// [A2AExecutionEventBus] as A2A protocol events.
///
/// Lightweight responses (no continuation token) are published as a single
/// `agent` message. Long-running responses surface task lifecycle events
/// (submitted/working/completed) so callers can track progress.
class A2AAgentHandler implements A2AAgentExecutor {
  /// Creates a handler that runs [hostAgent] using the given [runMode].
  A2AAgentHandler(this._hostAgent, this._runMode);

  final AIHostAgent _hostAgent;
  final AgentRunMode _runMode;

  @override
  Future<void> execute(
    A2ARequestContext requestContext,
    A2AExecutionEventBus eventBus,
  ) async {
    final contextId = requestContext.contextId.isNotEmpty
        ? requestContext.contextId
        : _generateUuid();
    final session = await _hostAgent.getOrCreateSession(contextId);
    try {
      if (requestContext.task != null) {
        await _handleTaskUpdate(requestContext, eventBus, contextId, session);
      } else {
        await _handleNewMessage(requestContext, eventBus, contextId, session);
      }
    } finally {
      await _hostAgent.saveSession(contextId, session);
    }
  }

  @override
  Future<void> cancelTask(String taskId, A2AExecutionEventBus eventBus) async {
    _TaskEvents(eventBus, taskId, '').cancel();
    eventBus.finished();
  }

  Future<void> _handleNewMessage(
    A2ARequestContext requestContext,
    A2AExecutionEventBus eventBus,
    String contextId,
    AgentSession session,
  ) async {
    // AIAgent cannot resume from arbitrary prior tasks; reject explicitly so
    // the caller gets a clear error rather than a silently ignored reference.
    if (requestContext.userMessage.referenceTaskIds?.isNotEmpty ?? false) {
      throw UnsupportedError(
        'ReferenceTaskIds is not supported. '
        'AIAgent cannot resume from arbitrary prior task context.',
      );
    }

    final chatMessages = [requestContext.userMessage.toChatMessage()];
    final allowBackground = await _runMode.shouldRunInBackground(
      A2ARunDecisionContext(requestContext),
    );
    final options = _buildOptions(requestContext, allowBackground);

    final response = await _hostAgent.run(
      session,
      options,
      messages: chatMessages,
    );

    if (response.continuationToken == null) {
      // Lightweight message response (no task lifecycle needed).
      eventBus.publish(_createMessageFromResponse(contextId, response));
    } else {
      // Long-running operation: emit task lifecycle events.
      final events = _TaskEvents(eventBus, requestContext.taskId, contextId);
      events.submit();
      events.startWork(_progressMessage(contextId, response));
    }
    eventBus.finished();
  }

  Future<void> _handleTaskUpdate(
    A2ARequestContext requestContext,
    A2AExecutionEventBus eventBus,
    String contextId,
    AgentSession session,
  ) async {
    final chatMessages = _extractChatMessages(requestContext.task);
    final allowBackground = await _runMode.shouldRunInBackground(
      A2ARunDecisionContext(requestContext),
    );
    final options = _buildOptions(requestContext, allowBackground);

    AgentResponse response;
    try {
      response = await _hostAgent.run(session, options, messages: chatMessages);
    } catch (_) {
      _TaskEvents(eventBus, requestContext.taskId, contextId).fail();
      rethrow;
    }

    final events = _TaskEvents(eventBus, requestContext.taskId, contextId);
    if (response.continuationToken == null) {
      // Complete the task with an artifact containing the response.
      events.addArtifact(response.toParts());
      events.complete();
    } else {
      // Still working: emit progress status.
      events.startWork(_progressMessage(contextId, response));
    }
    eventBus.finished();
  }

  AgentRunOptions _buildOptions(
    A2ARequestContext requestContext,
    bool allowBackground,
  ) {
    final options = AgentRunOptions()
      ..allowBackgroundResponses = allowBackground;
    final metadata = requestContext.userMessage.metadata;
    if (metadata != null && metadata.isNotEmpty) {
      options.additionalProperties = metadata.toAdditionalProperties();
    }
    return options;
  }

  A2AMessage? _progressMessage(String contextId, AgentResponse response) =>
      response.messages.isNotEmpty
      ? _createMessageFromResponse(contextId, response)
      : null;

  static A2AMessage _createMessageFromResponse(
    String contextId,
    AgentResponse response,
  ) {
    final message = A2AMessage()
      ..messageId = response.responseId ?? _generateUuid()
      ..contextId = contextId
      ..role = 'agent'
      ..parts = response.toParts();
    final metadata = response.additionalProperties;
    if (metadata != null) {
      message.metadata = metadata.toA2AMetadata();
    }
    return message;
  }

  static List<ChatMessage> _extractChatMessages(A2ATask? task) {
    final history = task?.history;
    if (history == null || history.isEmpty) {
      return const [];
    }
    return history.map((m) => m.toChatMessage()).toList();
  }
}

/// Publishes A2A task lifecycle events to an [A2AExecutionEventBus].
///
/// Replaces the C# `TaskUpdater` helper from the A2A SDK, which the Dart
/// package does not provide.
class _TaskEvents {
  _TaskEvents(this._eventBus, this._taskId, this._contextId);

  final A2AExecutionEventBus _eventBus;
  final String _taskId;
  final String _contextId;

  void submit() => _publishStatus(A2ATaskState.submitted);

  void startWork(A2AMessage? message) =>
      _publishStatus(A2ATaskState.working, message: message);

  void complete() => _publishStatus(A2ATaskState.completed, end: true);

  void cancel() => _publishStatus(A2ATaskState.canceled, end: true);

  void fail() => _publishStatus(A2ATaskState.failed, end: true);

  void addArtifact(List<A2APart> parts) {
    _eventBus.publish(
      A2ATaskArtifactUpdateEvent()
        ..taskId = _taskId
        ..contextId = _contextId
        ..lastChunk = true
        ..artifact = (A2AArtifact()
          ..artifactId = _generateUuid()
          ..parts = parts),
    );
  }

  void _publishStatus(A2ATaskState state, {A2AMessage? message, bool? end}) {
    final status = A2ATaskStatus()
      ..state = state
      ..timestamp = DateTime.now().toUtc().toIso8601String();
    if (message != null) {
      status.message = message;
    }
    final event = A2ATaskStatusUpdateEvent()
      ..taskId = _taskId
      ..contextId = _contextId
      ..status = status;
    if (end != null) {
      event.end = end;
    }
    _eventBus.publish(event);
  }
}

final _random = Random.secure();

String _generateUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final b = bytes.map(hex).toList();
  return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-'
      '${b[6]}${b[7]}-${b[8]}${b[9]}-'
      '${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
}
