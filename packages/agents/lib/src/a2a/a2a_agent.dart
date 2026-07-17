// Hide conflicting names from the a2a package:
// • Logger  — re-exported from darto via a2a_server, conflicts with extensions
// • A2AAgent — a2a's own marker base class, conflicts with our A2AAgent
import 'package:a2a/a2a.dart' hide Logger, A2AAgent;
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_update.dart';
import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/ai_agent_metadata.dart';
import 'a2a_agent_log_messages.dart';
import 'a2a_agent_options.dart';
import 'a2a_agent_session.dart';
import 'a2a_continuation_token.dart';
import 'extensions/a2a_agent_task_extensions.dart';
import 'extensions/a2a_ai_content_extensions.dart';
import 'extensions/a2a_artifact_extensions.dart';
import 'extensions/agent_task_status_extensions.dart';
import 'extensions/chat_message_extensions.dart';

/// An [AIAgent] that communicates with remote agents via the A2A protocol.
final class A2AAgent extends AIAgent {
  static final _agentMetadata = AIAgentMetadata(providerName: 'a2a');

  final A2AClient _a2aClient;
  final A2AAgentOptions _agentOptions;
  final Logger _logger;

  /// Creates an [A2AAgent] with individual identity fields.
  A2AAgent(
    A2AClient client, {
    String? id,
    String? name,
    String? description,
    LoggerFactory? loggerFactory,
  }) : this.withOptions(
         client,
         A2AAgentOptions(id: id, name: name, description: description),
         loggerFactory: loggerFactory,
       );

  /// Creates an [A2AAgent] from explicit [options].
  A2AAgent.withOptions(
    A2AClient client,
    A2AAgentOptions options, {
    LoggerFactory? loggerFactory,
  }) : _a2aClient = client,
       _agentOptions = options.clone(),
       _logger = (loggerFactory ?? NullLoggerFactory.instance).createLogger(
         'A2AAgent',
       );

  @override
  String? get idCore => _agentOptions.id;

  @override
  String? get name => _agentOptions.name;

  @override
  String? get description => _agentOptions.description;

  @override
  Object? getService(Type serviceType, {Object? serviceKey}) =>
      super.getService(serviceType, serviceKey: serviceKey) ??
      (serviceType == A2AClient
          ? _a2aClient
          : serviceType == AIAgentMetadata
          ? _agentMetadata
          : null);

  // ── Session management ───────────────────────────────────────────────────

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => A2AAgentSession();

  /// Creates a session linked to an existing [contextId] conversation.
  Future<AgentSession> createSessionWithContext(String contextId) async {
    if (contextId.isEmpty) throw ArgumentError.value(contextId, 'contextId');
    return A2AAgentSession()..contextId = contextId;
  }

  /// Creates a session linked to an existing [contextId] and [taskId].
  Future<AgentSession> createSessionWithTask(
    String contextId,
    String taskId,
  ) async {
    if (contextId.isEmpty) throw ArgumentError.value(contextId, 'contextId');
    if (taskId.isEmpty) throw ArgumentError.value(taskId, 'taskId');
    return A2AAgentSession()
      ..contextId = contextId
      ..taskId = taskId;
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    if (session is! A2AAgentSession) {
      throw ArgumentError(
        "Session type '${session.runtimeType}' is not compatible with "
        'A2AAgent. Only A2AAgentSession can be serialized.',
      );
    }
    return session.serialize();
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => A2AAgentSession.deserialize(serializedState as String);

  // ── Non-streaming run ────────────────────────────────────────────────────

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final inputMessages = messages.toList();
    final typedSession = await _getA2ASession(session, options);

    _logger.logA2AAgentInvokingAgent('run', id, name);

    final token = _getContinuationToken(inputMessages, options);
    if (token != null) {
      final taskResponse = await _a2aClient.getTask(
        A2ATaskQueryParams()..id = token.taskId,
      );
      _logger.logA2AAgentInvokedAgent('run', id, name);

      if (taskResponse is A2AGetTaskSuccessResponse) {
        final task = taskResponse.result;
        if (task != null) {
          _updateSession(
            typedSession,
            task.contextId,
            task.id,
            task.status?.state,
          );
          return _taskToAgentResponse(task);
        }
      }
      throw StateError(
        'Failed to retrieve task for continuation token ${token.taskId}.',
      );
    }

    final a2aMessage = inputMessages.toA2AMessage();
    _applySessionToMessage(typedSession, a2aMessage);

    final params = A2AMessageSendParams()
      ..message = a2aMessage
      ..metadata = _toA2AMetadata(options?.additionalProperties)
      ..configuration = options?.allowBackgroundResponses == true
          ? (A2AMessageSendConfiguration()..blocking = false)
          : null;

    final response = await _a2aClient.sendMessage(params);
    _logger.logA2AAgentInvokedAgent('run', id, name);

    if (response is A2ASendMessageSuccessResponse) {
      final result = response.result;
      if (result is A2AMessage) {
        _updateSession(typedSession, result.contextId);
        return _messageToAgentResponse(result);
      }
      if (result is A2ATask) {
        _updateSession(
          typedSession,
          result.contextId,
          result.id,
          result.status?.state,
        );
        return _taskToAgentResponse(result);
      }
    }

    throw UnsupportedError(
      'Only Message and AgentTask responses are supported from A2A agents.',
    );
  }

  // ── Streaming run ────────────────────────────────────────────────────────

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final inputMessages = messages.toList();
    final typedSession = await _getA2ASession(session, options);

    _logger.logA2AAgentInvokingAgent('runStreaming', id, name);

    Stream<A2ASendStreamMessageResponse> streamEvents;

    final token = _getContinuationToken(inputMessages, options);
    if (token != null) {
      streamEvents = _subscribeToTaskWithFallback(token.taskId);
    } else {
      final a2aMessage = inputMessages.toA2AMessage();
      _applySessionToMessage(typedSession, a2aMessage);

      final params = A2AMessageSendParams()
        ..message = a2aMessage
        ..metadata = _toA2AMetadata(options?.additionalProperties);

      streamEvents = _a2aClient.sendMessageStream(params);
    }

    _logger.logA2AAgentInvokedAgent('runStreaming', id, name);

    String? contextId;
    String? taskId;
    A2ATaskState? taskState;

    await for (final item in streamEvents) {
      if (item is! A2ASendStreamMessageSuccessResponse) continue;
      final result = item.result;

      if (result is A2AMessage) {
        contextId = result.contextId;
        yield _messageToAgentResponseUpdate(result);
      } else if (result is A2ATask) {
        contextId = result.contextId;
        taskId = result.id;
        taskState = result.status?.state;
        yield _taskToAgentResponseUpdate(result);
      } else if (result is A2ATaskStatusUpdateEvent) {
        contextId = result.contextId;
        taskId = result.taskId;
        taskState = result.status?.state;
        yield _statusUpdateToAgentResponseUpdate(result);
      } else if (result is A2ATaskArtifactUpdateEvent) {
        contextId = result.contextId;
        taskId = result.taskId;
        yield _artifactUpdateToAgentResponseUpdate(result);
      }
    }

    _updateSession(typedSession, contextId, taskId, taskState);
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  Future<A2AAgentSession> _getA2ASession(
    AgentSession? session,
    AgentRunOptions? options,
  ) async {
    if (options?.allowBackgroundResponses == true && session == null) {
      throw StateError(
        'A session must be provided when allowBackgroundResponses is enabled.',
      );
    }

    session ??= await createSession();

    if (session is! A2AAgentSession) {
      throw ArgumentError(
        "Session type '${session.runtimeType}' is not compatible with "
        'A2AAgent. Only A2AAgentSession can be used.',
      );
    }

    return session;
  }

  /// Subscribes to task updates, falling back to [A2AClient.getTask] when
  /// the task has already reached a terminal state (the server responds with
  /// `UnsupportedOperation`).
  Stream<A2ASendStreamMessageResponse> _subscribeToTaskWithFallback(
    String taskId,
  ) async* {
    final params = A2ATaskIdParams()..id = taskId;
    await for (final item in _a2aClient.resubscribeTask(params)) {
      if (item.isError && item is A2AJSONRPCErrorResponseSSM) {
        final errorCode = item.error?.rpcErrorCode ?? A2AError.unknown;
        if (errorCode == A2AError.unsupportedOperation) {
          final errorMsg = item.error is A2AUnsupportedOperationError
              ? (item.error as A2AUnsupportedOperationError).message
              : 'unsupported operation';
          _logger.logA2ASubscribeToTaskFallback(id, name, taskId, errorMsg);

          final taskResponse = await _a2aClient.getTask(
            A2ATaskQueryParams()..id = taskId,
          );
          if (taskResponse is A2AGetTaskSuccessResponse &&
              taskResponse.result != null) {
            yield A2ASendStreamMessageSuccessResponse()
              ..result = taskResponse.result;
          }
          return;
        }
      }
      yield item;
    }
  }

  static void _updateSession(
    A2AAgentSession? session,
    String? contextId, [
    String? taskId,
    A2ATaskState? taskState,
  ]) {
    if (session == null) return;

    if (session.contextId != null &&
        contextId != null &&
        session.contextId != contextId) {
      throw StateError(
        'The contextId returned from the A2A agent differs from the '
        "session's contextId.",
      );
    }

    session.contextId ??= contextId;
    session.taskId = taskId;
    session.taskState = taskState;
  }

  static void _applySessionToMessage(
    A2AAgentSession session,
    A2AMessage message,
  ) {
    message.contextId = session.contextId;
    if (session.taskState == A2ATaskState.inputRequired) {
      message.taskId = session.taskId;
    } else {
      final tid = session.taskId;
      message.referenceTaskIds = tid != null ? [tid] : null;
    }
  }

  static A2AContinuationToken? _getContinuationToken(
    List<ChatMessage> messages,
    AgentRunOptions? options,
  ) {
    final raw = options?.continuationToken;
    if (raw is! ResponseContinuationToken) return null;

    if (messages.isNotEmpty) {
      throw ArgumentError(
        'Messages are not allowed when continuing a background response '
        'using a continuation token.',
      );
    }

    return A2AContinuationToken.fromToken(raw);
  }

  static A2AContinuationToken? _createContinuationToken(
    String taskId,
    A2ATaskState? state,
  ) {
    if (state == A2ATaskState.submitted || state == A2ATaskState.working) {
      return A2AContinuationToken(taskId);
    }
    return null;
  }

  static ChatFinishReason? _mapTaskStateToFinishReason(A2ATaskState? state) =>
      state == A2ATaskState.completed ? ChatFinishReason.stop : null;

  static Map<String, dynamic>? _toA2AMetadata(
    AdditionalPropertiesDictionary? properties,
  ) {
    if (properties == null) return null;
    return Map<String, dynamic>.from(properties);
  }

  // ── Response converters ──────────────────────────────────────────────────

  AgentResponse _messageToAgentResponse(A2AMessage message) =>
      AgentResponse(messages: [message.toChatMessage()])
        ..agentId = id
        ..responseId = message.messageId
        ..finishReason = ChatFinishReason.stop
        ..rawRepresentation = message
        ..additionalProperties = message.metadata != null
            ? Map<String, Object?>.from(message.metadata!)
            : null;

  AgentResponse _taskToAgentResponse(A2ATask task) =>
      AgentResponse(messages: task.toChatMessages() ?? [])
        ..agentId = id
        ..responseId = task.id
        ..finishReason = _mapTaskStateToFinishReason(task.status?.state)
        ..rawRepresentation = task
        ..continuationToken = _createContinuationToken(
          task.id,
          task.status?.state,
        )
        ..additionalProperties = task.metadata != null
            ? Map<String, Object?>.from(task.metadata!)
            : null;

  AgentResponseUpdate _messageToAgentResponseUpdate(A2AMessage message) =>
      AgentResponseUpdate(
          role: message.role == 'user' ? ChatRole.user : ChatRole.assistant,
          contents: (message.parts ?? []).map((p) => p.toAIContent()).toList(),
        )
        ..agentId = id
        ..responseId = message.messageId
        ..messageId = message.messageId
        ..finishReason = ChatFinishReason.stop
        ..rawRepresentation = message
        ..additionalProperties = message.metadata != null
            ? Map<String, Object?>.from(message.metadata!)
            : null;

  AgentResponseUpdate _taskToAgentResponseUpdate(A2ATask task) =>
      AgentResponseUpdate(
          role: ChatRole.assistant,
          contents: task.toAIContents(),
        )
        ..agentId = id
        ..responseId = task.id
        ..finishReason = _mapTaskStateToFinishReason(task.status?.state)
        ..rawRepresentation = task
        ..continuationToken = _createContinuationToken(
          task.id,
          task.status?.state,
        )
        ..additionalProperties = task.metadata != null
            ? Map<String, Object?>.from(task.metadata!)
            : null;

  AgentResponseUpdate _statusUpdateToAgentResponseUpdate(
    A2ATaskStatusUpdateEvent event,
  ) =>
      AgentResponseUpdate(
          role: ChatRole.assistant,
          contents: event.status?.getUserInputRequests() ?? [],
        )
        ..agentId = id
        ..responseId = event.taskId
        ..messageId = event.status?.message?.messageId
        ..finishReason = _mapTaskStateToFinishReason(event.status?.state)
        ..rawRepresentation = event
        ..additionalProperties = event.metadata != null
            ? Map<String, Object?>.from(event.metadata!)
            : null;

  AgentResponseUpdate _artifactUpdateToAgentResponseUpdate(
    A2ATaskArtifactUpdateEvent event,
  ) =>
      AgentResponseUpdate(
          role: ChatRole.assistant,
          contents: event.artifact?.toAIContents() ?? [],
        )
        ..agentId = id
        ..responseId = event.taskId
        ..rawRepresentation = event
        ..additionalProperties = event.metadata != null
            ? Map<String, Object?>.from(event.metadata!)
            : null;
}
