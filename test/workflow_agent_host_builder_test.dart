import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/workflows/agent_response_update_event.dart';
import 'package:agents/src/workflows/agent_workflow_builder.dart';
import 'package:agents/src/workflows/ai_agent_extensions.dart';
import 'package:agents/src/workflows/ai_agent_host_options.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/in_process_execution.dart';
import 'package:agents/src/workflows/specialized/aggregate_turn_messages_executor.dart';
import 'package:agents/src/workflows/specialized/ai_agent_host_executor.dart';
import 'package:agents/src/workflows/specialized/concurrent_end_executor.dart';
import 'package:agents/src/workflows/specialized/output_messages_executor.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:agents/src/workflows/workflow_context.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AIAgentHostOptions', () {
    test('defaults match upstream behavior', () {
      const options = AIAgentHostOptions();

      expect(options.emitAgentUpdateEvents, isNull);
      expect(options.emitAgentResponseEvents, isFalse);
      expect(options.interceptUserInputRequests, isFalse);
      expect(options.interceptUnterminatedFunctionCalls, isFalse);
      expect(options.reassignOtherAgentsAsUsers, isTrue);
      expect(options.forwardIncomingMessages, isTrue);
    });

    test('copyWith updates selected values', () {
      const options = AIAgentHostOptions();
      final updated = options.copyWith(
        emitAgentUpdateEvents: true,
        forwardIncomingMessages: false,
      );

      expect(updated.emitAgentUpdateEvents, isTrue);
      expect(updated.forwardIncomingMessages, isFalse);
      expect(updated.reassignOtherAgentsAsUsers, isTrue);
    });
  });

  group('AIAgentHostExecutor', () {
    test(
      'forwards incoming messages and generated response messages',
      () async {
        final agent = _ScriptedAgent(
          name: 'agent',
          onRun: (messages, options) =>
              _assistant('reply:${messages.single.text}'),
        );
        final executor = AIAgentHostExecutor(agent);
        final context = CollectingWorkflowContext(executor.id);

        final output = await executor.handle([
          ChatMessage.fromText(ChatRole.user, 'hello'),
        ], context);

        expect(output.map((message) => message.text), ['hello', 'reply:hello']);
        expect(output.last.authorName, 'agent');
        expect(agent.createSessionCount, 1);
      },
    );

    test('reassigns other assistant participants as user messages', () async {
      late List<ChatMessage> captured;
      final agent = _ScriptedAgent(
        name: 'target',
        onRun: (messages, options) {
          captured = messages;
          return _assistant('done');
        },
      );
      final executor = AIAgentHostExecutor(agent);

      await executor.handle([
        ChatMessage(
          role: ChatRole.assistant,
          contents: [TextContent('from other')],
          authorName: 'other',
        ),
      ], CollectingWorkflowContext(executor.id));

      expect(captured.single.role, ChatRole.user);
    });

    test('can suppress forwarding incoming messages', () async {
      final agent = _ScriptedAgent(
        name: 'agent',
        onRun: (messages, options) => _assistant('reply'),
      );
      final executor = AIAgentHostExecutor(
        agent,
        options: const AIAgentHostOptions(forwardIncomingMessages: false),
      );

      final output = await executor.handle([
        ChatMessage.fromText(ChatRole.user, 'hello'),
      ], CollectingWorkflowContext(executor.id));

      expect(output.map((message) => message.text), ['reply']);
    });

    test('emits streaming update events when configured', () async {
      final agent = _ScriptedAgent(
        name: 'agent',
        onStream: (messages, options) => [
          AgentResponseUpdate(role: ChatRole.assistant, content: 'one'),
          AgentResponseUpdate(role: ChatRole.assistant, content: 'two'),
        ],
      );
      final executor = AIAgentHostExecutor(
        agent,
        options: const AIAgentHostOptions(emitAgentUpdateEvents: true),
      );
      final context = CollectingWorkflowContext(executor.id);

      final output = await executor.handle([
        ChatMessage.fromText(ChatRole.user, 'hello'),
      ], context);

      expect(context.outputs.whereType<AgentResponseUpdateEvent>().length, 2);
      expect(output.map((message) => message.text), ['hello', 'one', 'two']);
    });

    test('bindAsExecutor extension creates host binding', () async {
      final agent = _ScriptedAgent(name: 'agent');
      final binding = agent.bindAsExecutor();

      expect(binding.id, 'agent');
      expect(await binding.createInstance(), isA<AIAgentHostExecutor>());
    });
  });

  group('AgentWorkflowBuilder sequential and concurrent', () {
    test(
      'buildSequential runs agents in order and outputs full history',
      () async {
        final workflow = AgentWorkflowBuilder.buildSequential([
          _ScriptedAgent(
            name: 'agent1',
            onRun: (messages, options) =>
                _assistant('agent1:${messages.map((m) => m.text).join(",")}'),
          ),
          _ScriptedAgent(
            name: 'agent2',
            onRun: (messages, options) =>
                _assistant('agent2:${messages.map((m) => m.text).join(",")}'),
          ),
        ], workflowName: 'Sequential');

        final output = await _runForMessages(workflow, [
          ChatMessage.fromText(ChatRole.user, 'abc'),
        ]);

        expect(workflow.name, 'Sequential');
        expect(output.map((message) => message.text), [
          'abc',
          'agent1:abc',
          'agent2:abc,agent1:abc',
        ]);
        expect(output[1].authorName, 'agent1');
        expect(output[2].authorName, 'agent2');
      },
    );

    test(
      'buildConcurrent runs all agents and returns last message from each',
      () async {
        final workflow = AgentWorkflowBuilder.buildConcurrent([
          _ScriptedAgent(
            name: 'agent1',
            onRun: (messages, options) =>
                _assistant('agent1:${messages.last.text}'),
          ),
          _ScriptedAgent(
            name: 'agent2',
            onRun: (messages, options) =>
                _assistant('agent2:${messages.last.text}'),
          ),
        ], workflowName: 'Concurrent');

        final output = await _runForMessages(workflow, [
          ChatMessage.fromText(ChatRole.user, 'abc'),
        ]);

        expect(workflow.name, 'Concurrent');
        expect(output.map((message) => message.text).toSet(), {
          'agent1:abc',
          'agent2:abc',
        });
      },
    );

    test('buildConcurrent accepts custom aggregator', () async {
      final workflow = AgentWorkflowBuilder.buildConcurrent(
        [
          _ScriptedAgent(
            name: 'agent1',
            onRun: (_, options) => _assistant('one'),
          ),
          _ScriptedAgent(
            name: 'agent2',
            onRun: (_, options) => _assistant('two'),
          ),
        ],
        aggregator: (lists) {
          final texts = [
            for (final list in lists)
              if (list.isNotEmpty) list.last.text,
          ]..sort();
          return [ChatMessage.fromText(ChatRole.assistant, texts.join('+'))];
        },
      );

      final output = await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'abc'),
      ]);

      expect(output.single.text, 'one+two');
    });

    test('sequential and concurrent validate empty agents', () {
      expect(
        () => AgentWorkflowBuilder.buildSequential(const <AIAgent>[]),
        throwsArgumentError,
      );
      expect(
        () => AgentWorkflowBuilder.buildConcurrent(const <AIAgent>[]),
        throwsArgumentError,
      );
    });
  });

  group('Specialized message executors', () {
    test('output and aggregate executors normalize chat messages', () async {
      final output = OutputMessagesExecutor();
      final aggregate = AggregateTurnMessagesExecutor('aggregate');
      final input = ChatMessage.fromText(ChatRole.user, 'hello');

      expect(
        (await output.handle(
          input,
          CollectingWorkflowContext(output.id),
        )).single.text,
        'hello',
      );
      expect(
        (await aggregate.handle(
          input,
          CollectingWorkflowContext(aggregate.id),
        )).single.text,
        'hello',
      );
    });

    test('concurrent end aggregates message lists', () async {
      final executor = ConcurrentEndExecutor(
        2,
        (lists) => [for (final list in lists) list.last],
      );
      final result = await executor.handle([
        [ChatMessage.fromText(ChatRole.assistant, 'one')],
        [ChatMessage.fromText(ChatRole.assistant, 'two')],
      ], CollectingWorkflowContext(executor.id));

      expect(result.map((message) => message.text), ['one', 'two']);
    });

    test('host executor can be used directly in a workflow', () async {
      final agent = _ScriptedAgent(
        name: 'agent',
        onRun: (messages, options) => _assistant('reply'),
      );
      final executor = AIAgentHostExecutor(agent);
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(executor),
      ).addOutput(executor.id).build();

      final output = await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'hello'),
      ]);

      expect(output.map((message) => message.text), ['hello', 'reply']);
    });
  });
}

Future<List<ChatMessage>> _runForMessages(
  dynamic workflow,
  List<ChatMessage> input,
) async {
  final run = await inProcessExecution.runAsync(workflow, input);
  return List<ChatMessage>.of(
    run.outgoingEvents.whereType<WorkflowOutputEvent>().last.data
        as List<ChatMessage>,
  );
}

AgentResponse _assistant(String text) =>
    AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, text));

class _ScriptedAgent extends AIAgent {
  _ScriptedAgent({
    String? name,
    AgentResponse Function(
      List<ChatMessage> messages,
      AgentRunOptions? options,
    )?
    onRun,
    List<AgentResponseUpdate> Function(
      List<ChatMessage> messages,
      AgentRunOptions? options,
    )?
    onStream,
  }) : _name = name,
       _onRun = onRun,
       _onStream = onStream;

  final String? _name;
  final AgentResponse Function(
    List<ChatMessage> messages,
    AgentRunOptions? options,
  )?
  _onRun;
  final List<AgentResponseUpdate> Function(
    List<ChatMessage> messages,
    AgentRunOptions? options,
  )?
  _onStream;
  int createSessionCount = 0;

  @override
  String? get name => _name;

  @override
  String? get description => null;

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
  }) async => null;

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
    final list = List<ChatMessage>.of(messages);
    return _onRun?.call(list, options) ?? _assistant(name ?? 'agent');
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final list = List<ChatMessage>.of(messages);
    final updates =
        _onStream?.call(list, options) ??
        (await runCore(
          list,
          session: session,
          options: options,
          cancellationToken: cancellationToken,
        )).toAgentResponseUpdates();
    for (final update in updates) {
      yield update;
    }
  }
}

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}
