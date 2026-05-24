import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_extensions.dart';
import '../abstractions/agent_response_update.dart';
import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/delegating_ai_agent.dart';

/// Function type for a shared delegate that handles both run and streaming.
///
/// The [innerInvoker] parameter is a callback that invokes the inner agent and
/// returns its response (non-streaming).
typedef SharedAgentRunDelegate =
    Future<AgentResponse> Function(
      Iterable<ChatMessage> messages,
      AgentSession? session,
      AgentRunOptions? options,
      Future<AgentResponse> Function(
        Iterable<ChatMessage>,
        AgentSession?,
        AgentRunOptions?,
        CancellationToken?,
      )
      innerInvoker,
      CancellationToken? cancellationToken,
    );

/// Function type for a custom non-streaming agent run delegate.
typedef RunAgentDelegate =
    Future<AgentResponse> Function(
      Iterable<ChatMessage> messages,
      AgentSession? session,
      AgentRunOptions? options,
      AIAgent innerAgent,
      CancellationToken? cancellationToken,
    );

/// Function type for a custom streaming agent run delegate.
typedef RunStreamingAgentDelegate =
    Stream<AgentResponseUpdate> Function(
      Iterable<ChatMessage> messages,
      AgentSession? session,
      AgentRunOptions? options,
      AIAgent innerAgent,
      CancellationToken? cancellationToken,
    );

/// Represents a delegating AI agent that wraps an inner agent with
/// implementations provided by delegates.
///
/// This is a convenience implementation mainly used to support
/// [AIAgentBuilder] `use` methods that take delegates to intercept agent
/// operations.
class AnonymousDelegatingAIAgent extends DelegatingAIAgent {
  /// Creates an [AnonymousDelegatingAIAgent] from an [innerAgent] and at
  /// least one of [sharedFunc], [runFunc], or [runStreamingFunc].
  AnonymousDelegatingAIAgent(
    super.innerAgent, {
    SharedAgentRunDelegate? sharedFunc,
    RunAgentDelegate? runFunc,
    RunStreamingAgentDelegate? runStreamingFunc,
  }) : _sharedFunc = sharedFunc,
       _runFunc = runFunc,
       _runStreamingFunc = runStreamingFunc {
    throwIfBothDelegatesNull(runFunc, runStreamingFunc);
  }

  final SharedAgentRunDelegate? _sharedFunc;
  final RunAgentDelegate? _runFunc;
  final RunStreamingAgentDelegate? _runStreamingFunc;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    if (_sharedFunc != null) {
      return _sharedFunc(
        messages,
        session,
        options,
        (m, s, o, ct) => innerAgent.runCore(
          m,
          session: s,
          options: o,
          cancellationToken: ct,
        ),
        cancellationToken,
      );
    } else if (_runFunc != null) {
      return _runFunc(
        messages,
        session,
        options,
        innerAgent,
        cancellationToken,
      );
    } else {
      return _runStreamingFunc!(
        messages,
        session,
        options,
        innerAgent,
        cancellationToken,
      ).toAgentResponseAsync(cancellationToken: cancellationToken);
    }
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    if (_sharedFunc != null) {
      return _streamFromShared(messages, session, options, cancellationToken);
    } else if (_runStreamingFunc != null) {
      return _runStreamingFunc(
        messages,
        session,
        options,
        innerAgent,
        cancellationToken,
      );
    } else {
      return _streamFromRun(
        _runFunc!(messages, session, options, innerAgent, cancellationToken),
      );
    }
  }

  Stream<AgentResponseUpdate> _streamFromShared(
    Iterable<ChatMessage> messages,
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  ) async* {
    final response = await _sharedFunc!(
      messages,
      session,
      options,
      (m, s, o, ct) =>
          innerAgent.runCore(m, session: s, options: o, cancellationToken: ct),
      cancellationToken,
    );
    for (final update in response.toAgentResponseUpdates()) {
      yield update;
    }
  }

  static Stream<AgentResponseUpdate> _streamFromRun(
    Future<AgentResponse> task,
  ) async* {
    final response = await task;
    for (final update in response.toAgentResponseUpdates()) {
      yield update;
    }
  }

  /// Throws if both [runFunc] and [runStreamingFunc] are `null`.
  static void throwIfBothDelegatesNull(
    Object? runFunc,
    Object? runStreamingFunc,
  ) {
    if (runFunc == null && runStreamingFunc == null) {
      throw ArgumentError(
        'At least one of runFunc or runStreamingFunc must be non-null.',
      );
    }
  }
}
