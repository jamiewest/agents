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
  AIAgent();

  static final _random = Random.secure();

  static String _generateId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  final String _defaultId = _generateId();

  /// Gets the unique identifier for this agent instance.
  ///
  /// Defaults to a randomly-generated identifier; service-backed agents can
  /// supply the identifier assigned by the backing service via [idCore].
  String get id => idCore ?? _defaultId;

  /// A custom identifier for the agent, which derived classes can override.
  ///
  /// When `null`, [id] uses the default randomly-generated identifier.
  String? get idCore => null;

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
  /// it wraps. Dart cannot test a runtime [Type] for assignability, so this
  /// base implementation only answers exact-type requests; [getServiceOf]
  /// additionally matches supertypes of the concrete agent type.
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceKey == null &&
            (serviceType == runtimeType || serviceType == AIAgent)
        ? this
        : null;
  }

  /// Returns a service of type [T], or `null`.
  T? getServiceOf<T extends Object>({Object? serviceKey}) {
    final service = getService(T, serviceKey: serviceKey);
    if (service is T) {
      return service;
    }
    return serviceKey == null && this is T ? this as T : null;
  }

  /// Creates a new conversation session compatible with this agent.
  Future<AgentSession> createSession({CancellationToken? cancellationToken}) {
    return createSessionCore(cancellationToken: cancellationToken);
  }

  /// Core implementation of session creation logic.
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  });

  /// Serializes an agent session to a JSON-compatible map.
  Future<dynamic> serializeSession(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    return serializeSessionCore(
      session,
      jsonSerializerOptions: jsonSerializerOptions,
      cancellationToken: cancellationToken,
    );
  }

  /// Core implementation of session serialization.
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  });

  /// Deserializes an agent session from a previously serialized state.
  Future<AgentSession> deserializeSession(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    return deserializeSessionCore(
      serializedState,
      jsonSerializerOptions: jsonSerializerOptions,
      cancellationToken: cancellationToken,
    );
  }

  /// Core implementation of session deserialization.
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
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
    currentRunContext = AgentRunContext(this, session, allMessages, options);
    return runCore(
      allMessages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
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
  }) async* {
    final allMessages = [
      if (message != null)
        ChatMessage(role: ChatRole.user, contents: [TextContent(message)]),
      ...?messages,
    ];
    final context = AgentRunContext(this, session, allMessages, options);
    currentRunContext = context;
    final updates = runCoreStreaming(
      allMessages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
    await for (final update in updates) {
      yield update;

      // Restore context again when resuming after the caller code executes.
      currentRunContext = context;
    }
  }

  /// Core implementation of the agent streaming invocation logic.
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  });
}
