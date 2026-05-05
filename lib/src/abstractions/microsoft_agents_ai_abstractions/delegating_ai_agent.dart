import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_response.dart';
import 'agent_response_update.dart';
import 'agent_run_options.dart';
import 'agent_session.dart';
import 'ai_agent.dart';

/// Abstract base class for AI agents that delegate operations to an inner
/// agent while allowing extensibility via the decorator pattern.
abstract class DelegatingAIAgent extends AIAgent {
  /// Creates a [DelegatingAIAgent] wrapping [innerAgent].
  DelegatingAIAgent(this.innerAgent);

  /// The underlying agent that receives delegated operations.
  final AIAgent innerAgent;

  @override
  String? get name => innerAgent.name;

  @override
  String? get description => innerAgent.description;

  @override
  Object? getService(Type serviceType, {Object? serviceKey}) {
    return serviceType == runtimeType
        ? this
        : innerAgent.getService(serviceType, serviceKey: serviceKey);
  }

  @override
  Future<AgentSession> createSessionCore({CancellationToken? cancellationToken}) {
    return innerAgent.createSession(cancellationToken: cancellationToken);
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    return innerAgent.serializeSession(
      session,
      JsonSerializerOptions: JsonSerializerOptions,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    return innerAgent.deserializeSession(
      serializedState,
      JsonSerializerOptions: JsonSerializerOptions,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return innerAgent.runCore(
      messages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return innerAgent.runCoreStreaming(
      messages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
  }
}
