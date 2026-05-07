import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'agent_response_event.dart';
import 'agent_response_update_event.dart';
import 'chat_protocol.dart';
import 'in_process_execution.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';
import 'workflow_output_event.dart';
import 'workflow_session.dart';

/// Hosts a [Workflow] behind the [AIAgent] abstraction.
class WorkflowHostAgent extends AIAgent {
  /// Creates an agent that runs [workflow].
  WorkflowHostAgent(
    this.workflow, {
    WorkflowExecutionEnvironment? executionEnvironment,
    String? name,
    String? description,
  }) : executionEnvironment = executionEnvironment ?? inProcessExecution,
       _name = name ?? workflow.name,
       _description = description ?? workflow.description;

  /// Gets the hosted workflow.
  final Workflow workflow;

  /// Gets the environment used to execute the workflow.
  final WorkflowExecutionEnvironment executionEnvironment;

  final String? _name;
  final String? _description;

  @override
  String? get name => _name;

  @override
  String? get description => _description;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return WorkflowHostAgentSession();
  }

  @override
  Future<String> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final workflowSession = _asWorkflowSession(session);
    return jsonEncode(<String, Object?>{
      'sessionId': workflowSession.sessionId,
      'stateBag': workflowSession.stateBag.serialize(),
    });
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedSession, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final data = serializedSession is String
        ? jsonDecode(serializedSession) as Map<String, Object?>
        : Map<String, Object?>.from(serializedSession as Map);
    return WorkflowHostAgentSession(
      sessionId: data['sessionId'] as String?,
      stateBag: AgentSessionStateBag.deserialize(data['stateBag'] as String?),
    );
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final workflowSession = _asWorkflowSession(
      session ?? await createSession(cancellationToken: cancellationToken),
    );
    final run = await executionEnvironment.runAsync(
      workflow,
      List<ChatMessage>.of(messages),
      sessionId: workflowSession.sessionId,
      cancellationToken: cancellationToken,
    );
    workflowSession.sessionId = run.sessionId;

    final responseMessages = <ChatMessage>[];
    for (final event in run.outgoingEvents) {
      switch (event) {
        case AgentResponseEvent(:final response):
          responseMessages.addAll(response.messages);
        case WorkflowOutputEvent(:final data):
          responseMessages.addAll(ChatProtocol.toResponseMessages(data));
      }
    }

    return AgentResponse(messages: responseMessages);
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final workflowSession = _asWorkflowSession(
      session ?? await createSession(cancellationToken: cancellationToken),
    );
    final run = await executionEnvironment.streamAsync(
      workflow,
      input: List<ChatMessage>.of(messages),
      sessionId: workflowSession.sessionId,
      cancellationToken: cancellationToken,
    );
    workflowSession.sessionId = run.sessionId;

    var yieldedStreamingUpdate = false;
    final bufferedResponseMessages = <ChatMessage>[];
    for (final event in run.outgoingEvents) {
      switch (event) {
        case AgentResponseUpdateEvent(:final update):
          yieldedStreamingUpdate = true;
          yield update;
        case AgentResponseEvent(:final response):
          bufferedResponseMessages.addAll(response.messages);
        case WorkflowOutputEvent(:final data):
          bufferedResponseMessages.addAll(
            ChatProtocol.toResponseMessages(data),
          );
      }
    }

    if (!yieldedStreamingUpdate) {
      final response = AgentResponse(messages: bufferedResponseMessages);
      for (final update in response.toAgentResponseUpdates()) {
        yield update;
      }
    }
  }

  WorkflowHostAgentSession _asWorkflowSession(AgentSession session) {
    if (session is WorkflowHostAgentSession) {
      return session;
    }
    throw ArgumentError.value(
      session,
      'session',
      'Session must be a WorkflowHostAgentSession.',
    );
  }
}

/// Agent session used by [WorkflowHostAgent].
class WorkflowHostAgentSession extends AgentSession {
  /// Creates a workflow host agent session.
  WorkflowHostAgentSession({String? sessionId, AgentSessionStateBag? stateBag})
    : sessionId = sessionId ?? WorkflowSession.createSessionId(),
      super(stateBag ?? AgentSessionStateBag(null));

  /// Gets the workflow session identifier.
  String sessionId;
}
