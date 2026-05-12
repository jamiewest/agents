import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/workflows/ai_agent_binding.dart';
import 'package:agents/src/workflows/ai_agent_extensions.dart';
import 'package:agents/src/workflows/ai_agents_abstractions_extensions.dart';
import 'package:agents/src/workflows/chat_forwarding_executor.dart';
import 'package:agents/src/workflows/chat_protocol.dart';
import 'package:agents/src/workflows/chat_protocol_executor.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/function_executor.dart';
import 'package:agents/src/workflows/in_process_execution.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_context.dart';
import 'package:agents/src/workflows/workflow_host_agent.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('ChatProtocol', () {
    test('normalizes common chat input shapes', () {
      final message = ChatMessage.fromText(ChatRole.user, 'hello');
      final response = AgentResponse(message: message);

      expect(ChatProtocol.toChatMessages('hello').single.text, 'hello');
      expect(ChatProtocol.toChatMessages(message), [message]);
      expect(ChatProtocol.toChatMessages([message]), [message]);
      expect(ChatProtocol.toChatMessages(response), [message]);
    });
  });

  group('ChatProtocolExecutor', () {
    test('invokes agent with chat messages and reuses session', () async {
      final agent = _FakeAgent(responseText: 'pong');
      final executor = ChatProtocolExecutor(agent, id: 'agent');
      final context = CollectingWorkflowContext('agent');

      final first = await executor.handle('ping', context);
      final second = await executor.handle(
        ChatMessage.fromText(ChatRole.user, 'again'),
        context,
      );

      expect(first.text, 'pong');
      expect(second.text, 'pong');
      expect(agent.createSessionCount, 1);
      expect(agent.runMessages.map((messages) => messages.single.text), [
        'ping',
        'again',
      ]);
      expect(executor.protocol.accepts(String), isTrue);
      expect(executor.protocol.produces(AgentResponse), isTrue);
    });

    test('agent extension creates executor and binding', () async {
      final agent = _FakeAgent(responseText: 'ok');

      expect(
        agent.asWorkflowExecutor(id: 'agent'),
        isA<ChatProtocolExecutor>(),
      );
      expect(
        agent.asWorkflowExecutorBinding(id: 'agent'),
        isA<AIAgentBinding>(),
      );
    });
  });

  group('AIAgentBinding', () {
    test('binds an agent as workflow start executor', () async {
      final agent = _FakeAgent(responseText: 'done');
      final workflow = WorkflowBuilder(
        AIAgentBinding(agent, id: 'agent'),
      ).addOutput('agent').build();

      final run = await inProcessExecution.runAsync(workflow, 'work');

      final response = _outputs(run.outgoingEvents).single as AgentResponse;
      expect(response.text, 'done');
      expect(agent.runMessages.single.single.text, 'work');
    });
  });

  group('ChatForwardingExecutor', () {
    test('forwards chat messages to target executor', () async {
      final executor = ChatForwardingExecutor('forward', 'agent');
      final context = CollectingWorkflowContext('forward');

      await executor.handle('hello', context);

      final sent = context.sentMessages.single as ChatMessage;
      expect(sent.text, 'hello');
    });
  });

  group('WorkflowHostAgent', () {
    test('runs workflow and returns output as agent response', () async {
      final start = FunctionExecutor<List<ChatMessage>, AgentResponse>(
        'start',
        (input, context, cancellationToken) => AgentResponse(
          message: ChatMessage.fromText(
            ChatRole.assistant,
            'echo:${input.single.text}',
          ),
        ),
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).addOutput('start').build();
      final agent = WorkflowHostAgent(workflow, name: 'host');

      final session = await agent.createSession();
      final response = await agent.run(
        session,
        null,
        cancellationToken: CancellationToken.none,
        message: 'hello',
      );

      expect(agent.name, 'host');
      expect(session, isA<WorkflowHostAgentSession>());
      expect(response.text, 'echo:hello');
    });

    test('workflow extension exposes workflow as agent', () {
      final start = FunctionExecutor<List<ChatMessage>, AgentResponse>(
        'start',
        (input, context, cancellationToken) => AgentResponse(messages: input),
      );
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start)).build();

      expect(workflow.asAIAgent(name: 'workflow'), isA<WorkflowHostAgent>());
    });

    test('streams response updates from workflow output', () async {
      final start = FunctionExecutor<List<ChatMessage>, AgentResponse>(
        'start',
        (input, context, cancellationToken) => AgentResponse(
          message: ChatMessage.fromText(ChatRole.assistant, 'streamed'),
        ),
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).addOutput('start').build();
      final agent = WorkflowHostAgent(workflow);

      final updates = await agent
          .runStreaming(
            await agent.createSession(),
            null,
            cancellationToken: CancellationToken.none,
            message: 'go',
          )
          .toList();

      expect(updates.map((update) => update.text), ['streamed']);
    });

    test('serializes and deserializes workflow host session', () async {
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(
          FunctionExecutor<List<ChatMessage>, AgentResponse>(
            'start',
            (input, context, cancellationToken) =>
                AgentResponse(messages: input),
          ),
        ),
      ).build();
      final agent = WorkflowHostAgent(workflow);
      final session = await agent.createSession() as WorkflowHostAgentSession;

      final serialized = await agent.serializeSession(session);
      final restored = await agent.deserializeSession(serialized);

      expect(
        (restored as WorkflowHostAgentSession).sessionId,
        session.sessionId,
      );
    });
  });
}

List<Object?> _outputs(Iterable<Object?> events) =>
    events.whereType<WorkflowOutputEvent>().map((event) => event.data).toList();

class _FakeAgent extends AIAgent {
  _FakeAgent({required this.responseText});

  final String responseText;
  final List<List<ChatMessage>> runMessages = <List<ChatMessage>>[];
  int createSessionCount = 0;

  @override
  String? get name => 'fake';

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    createSessionCount++;
    return _FakeSession();
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => session.stateBag.serialize();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    runMessages.add(List<ChatMessage>.of(messages));
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, responseText),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    yield AgentResponseUpdate(role: ChatRole.assistant, content: responseText);
  }
}

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}
