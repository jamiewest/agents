// ignore_for_file: non_constant_identifier_names
import 'dart:math';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_response.dart';
import 'agent_response_update.dart';
import 'agent_run_context.dart';
import 'agent_run_options.dart';
import 'agent_session.dart';

/// Provides the base abstraction for all AI agents, defining the core
/// interface for agent interactions and conversation management.
abstract class AIAgent {
  AIAgent() : id = _generateId();

  static final _random = Random.secure();

  static String _generateId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Gets the unique identifier for this agent instance.
  final String id;

  /// Gets the human-readable name of the agent.
  String? get name => null;

  /// Gets a description of the agent's purpose and capabilities.
  String? get description => null;

  /// The [AgentRunContext] for the current agent run.
  static AgentRunContext? currentRunContext;

  String get debuggerDisplay {
    final n = name;
    return n != null ? 'id = $id, name = $n' : 'id = $id';
  }

  /// Returns a service of the specified [serviceType], or `null`.
  ///
  /// Used to retrieve strongly-typed services from this agent or any agents
  /// it wraps.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceType == AIAgent ? this : null;
  }

  /// Returns a service of type [T], or `null`.
  T? getServiceOf<T extends Object>() => getService(T) as T?;

  /// Creates a new conversation session compatible with this agent.
  Future<AgentSession> createSession({CancellationToken? cancellationToken}) {
    return createSessionCore(cancellationToken: cancellationToken);
  }

  /// Core implementation of session creation logic.
  Future<AgentSession> createSessionCore({CancellationToken? cancellationToken});

  /// Serializes an agent session to a JSON-compatible map.
  Future<dynamic> serializeSession(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    return serializeSessionCore(
      session,
      JsonSerializerOptions: JsonSerializerOptions,
      cancellationToken: cancellationToken,
    );
  }

  /// Core implementation of session serialization.
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  });

  /// Deserializes an agent session from a previously serialized state.
  Future<AgentSession> deserializeSession(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    return deserializeSessionCore(
      serializedState,
      JsonSerializerOptions: JsonSerializerOptions,
      cancellationToken: cancellationToken,
    );
  }

  /// Core implementation of session deserialization.
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  });

  /// Runs the agent with the provided messages and returns the full response.
  ///
  /// [message] and [messages] are optional additional inputs beyond what is
  /// already in [session].
  Future<AgentResponse> run(
    AgentSession? session,
    AgentRunOptions? options, {
    CancellationToken? cancellationToken,
    String? message,
    Iterable<ChatMessage>? messages,
  }) {
    final allMessages = [
      if (message != null)
        ChatMessage(role: ChatRole.user, contents: [TextContent(message)]),
      ...?messages,
    ];
    return runCore(allMessages, session: session, options: options,
        cancellationToken: cancellationToken);
  }

  /// Core implementation of the agent invocation logic.
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  });

  /// Runs the agent in streaming mode.
  Stream<AgentResponseUpdate> runStreaming(
    AgentSession? session,
    AgentRunOptions? options, {
    CancellationToken? cancellationToken,
    String? message,
    Iterable<ChatMessage>? messages,
  }) {
    final allMessages = [
      if (message != null)
        ChatMessage(role: ChatRole.user, contents: [TextContent(message)]),
      ...?messages,
    ];
    return runCoreStreaming(allMessages, session: session, options: options,
        cancellationToken: cancellationToken);
  }

  /// Core implementation of the agent streaming invocation logic.
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  });
}
