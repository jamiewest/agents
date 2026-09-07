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
/// The [AgentRunMode] the handler is registered with decides which A2A
/// artifact a new message is answered with: [AgentRunMode.returnMessage]
/// publishes one aggregated `agent` message, while [AgentRunMode.returnTask]
/// surfaces task lifecycle events (submitted/working/completed) so callers
/// can track progress. Continuations of an existing task are always task
/// responses and do not consult the run mode.
class A2AAgentHandler implements A2AAgentExecutor {
  /// Creates a handler that returns responses as the artifact selected by
  /// [runMode].
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
    // No eventBus.finished(): see _handleNewMessage.
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

    // Decide which A2A artifact to return based on the configured run mode.
    final returnTask = await _runMode.shouldReturnTask(
      A2ARunDecisionContext(requestContext),
    );
    final options = _buildOptions(requestContext);

    final response = await _hostAgent.run(
      session,
      options,
      messages: chatMessages,
    );

    if (returnTask) {
      final events = _TaskEvents(eventBus, requestContext.taskId, contextId);
      events.submit();
      if (response.continuationToken == null) {
        // The run finished within this call, so complete the task with the
        // aggregated result rather than leaving the caller polling.
        events.addArtifact(
          response.toParts(),
          metadata: response.additionalProperties?.toA2AMetadata(),
        );
        events.complete();
      } else {
        // Long-running operation: the caller obtains the rest by polling.
        events.startWork(_progressMessage(contextId, response));
      }
    } else {
      // The run mode selects a message, which is not a long-running entity,
      // so the whole run is aggregated into one message.
      eventBus.publish(_createMessageFromResponse(contextId, response));
    }
    // Deliberately no eventBus.finished(): the a2a package's execution
    // event queue drops still-buffered events once finished arrives, and
    // its generator already terminates when the buffer drains (a message
    // event also stops it).
  }

  Future<void> _handleTaskUpdate(
    A2ARequestContext requestContext,
    A2AExecutionEventBus eventBus,
    String contextId,
    AgentSession session,
  ) async {
    // Continuations of an existing task stay task responses; the run mode is
    // only consulted for new messages.
    final chatMessages = _extractChatMessages(requestContext.task);
    final options = _buildOptions(requestContext);

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
      events.addArtifact(
        response.toParts(),
        metadata: response.additionalProperties?.toA2AMetadata(),
      );
      events.complete();
    } else {
      // Still working: emit progress status.
      events.startWork(_progressMessage(contextId, response));
    }
    // No eventBus.finished(): see _handleNewMessage.
  }

  /// Builds the run options forwarded to the hosted agent.
  ///
  /// The run mode is deliberately not forwarded as
  /// `AgentRunOptions.allowBackgroundResponses`: it selects the A2A artifact
  /// this server returns, not how the agent runs.
  AgentRunOptions _buildOptions(A2ARequestContext requestContext) {
    final options = AgentRunOptions();
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

  void addArtifact(List<A2APart> parts, {Map<String, dynamic>? metadata}) {
    final artifact = A2AArtifact()
      ..artifactId = _generateUuid()
      ..parts = parts;
    if (metadata != null) {
      artifact.metadata = metadata;
    }
    _eventBus.publish(
      A2ATaskArtifactUpdateEvent()
        ..taskId = _taskId
        ..contextId = _contextId
        ..lastChunk = true
        ..artifact = artifact,
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
