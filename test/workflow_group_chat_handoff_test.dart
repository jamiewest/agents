import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_agent_run_options.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/agent_workflow_builder.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/handoff_tool_call_filtering_behavior.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/handoff_workflow_builder.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/in_process_execution.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/round_robin_group_chat_manager.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/specialized/handoff_messages_filter.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/specialized/handoff_state.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/specialized/multi_party_conversation.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_output_event.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('RoundRobinGroupChatManager', () {
    test('selectNextAgent cycles in order and wraps around', () async {
      final agent1 = _ScriptedAgent(name: 'agent1');
      final agent2 = _ScriptedAgent(name: 'agent2');
      final manager = RoundRobinGroupChatManager([agent1, agent2]);
      final history = <ChatMessage>[];

      expect(await manager.selectNextAgent(history), same(agent1));
      expect(await manager.selectNextAgent(history), same(agent2));
      expect(await manager.selectNextAgent(history), same(agent1));
    });

    test('shouldTerminate uses iteration count and custom function', () async {
      final agent = _ScriptedAgent(name: 'agent');
      final manager = RoundRobinGroupChatManager(
        [agent],
        shouldTerminateFunc: (_, messages, _) async =>
            messages.any((message) => message.text == 'done'),
      )..maximumIterationCount = 3;

      manager.iterationCount = 2;
      expect(await manager.shouldTerminate([]), isFalse);

      manager.iterationCount = 3;
      expect(await manager.shouldTerminate([]), isTrue);

      manager.iterationCount = 0;
      expect(
        await manager.shouldTerminate([
          ChatMessage.fromText(ChatRole.assistant, 'done'),
        ]),
        isTrue,
      );
    });

    test('reset clears iteration count and index', () async {
      final agent1 = _ScriptedAgent(name: 'agent1');
      final agent2 = _ScriptedAgent(name: 'agent2');
      final manager = RoundRobinGroupChatManager([agent1, agent2])
        ..iterationCount = 5;

      await manager.selectNextAgent([]);
      manager.reset();

      expect(manager.iterationCount, 0);
      expect(await manager.selectNextAgent([]), same(agent1));
    });

    test('constructor and maximum iteration count validate arguments', () {
      expect(() => RoundRobinGroupChatManager([]), throwsArgumentError);
      final manager = RoundRobinGroupChatManager([_ScriptedAgent(name: 'a')]);
      expect(manager.maximumIterationCount, 40);
      expect(() => manager.maximumIterationCount = 0, throwsRangeError);
      manager.maximumIterationCount = 1;
      expect(manager.maximumIterationCount, 1);
    });
  });

  group('GroupChatWorkflowBuilder', () {
    test('withName and withDescription set workflow metadata', () {
      final workflow =
          AgentWorkflowBuilder.createGroupChatBuilderWith(
                (agents) => RoundRobinGroupChatManager(agents),
              )
              .addParticipants([_ScriptedAgent(name: 'agent')])
              .withName('Test Group Chat')
              .withDescription('A test group chat workflow')
              .build();

      expect(workflow.name, 'Test Group Chat');
      expect(workflow.description, 'A test group chat workflow');
    });

    test('runs participants selected by group chat manager', () async {
      final agent1 = _ScriptedAgent(
        name: 'agent1',
        onRun: (messages, options) =>
            _assistant('agent1:${messages.last.text}'),
      );
      final agent2 = _ScriptedAgent(
        name: 'agent2',
        onRun: (messages, options) =>
            _assistant('agent2:${messages.last.text}'),
      );
      final workflow = AgentWorkflowBuilder.createGroupChatBuilderWith(
        (agents) =>
            RoundRobinGroupChatManager(agents)..maximumIterationCount = 2,
      ).addParticipants([agent1, agent2]).build();

      final output = await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'hello'),
      ]);

      expect(output.map((message) => message.text), [
        'hello',
        'agent1:hello',
        'agent2:agent1:hello',
      ]);
      expect(output[1].authorName, 'agent1');
      expect(output[2].authorName, 'agent2');
    });
  });

  group('HandoffWorkflowBuilder', () {
    test('validates duplicate handoff and missing reason', () {
      final initial = _ScriptedAgent(name: 'initial');
      final target = _ScriptedAgent(name: 'target');
      final unnamed = _ScriptedAgent();
      final builder = AgentWorkflowBuilder.createHandoffBuilderWith(initial);

      builder.withHandoff(initial, target);
      expect(() => builder.withHandoff(initial, target), throwsStateError);
      expect(
        () => AgentWorkflowBuilder.createHandoffBuilderWith(
          initial,
        ).withHandoff(initial, unnamed),
        throwsArgumentError,
      );
    });

    test('no transfer returns response from initial agent', () async {
      final initial = _ScriptedAgent(
        name: 'initial',
        onRun: (messages, options) => _assistant('Hello from initial'),
      );
      final target = _ScriptedAgent(
        name: 'target',
        description: 'Target agent',
        onRun: (messages, options) {
          fail('Target should not be invoked.');
        },
      );
      final workflow = AgentWorkflowBuilder.createHandoffBuilderWith(
        initial,
      ).withHandoff(initial, target).build();

      final output = await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'abc'),
      ]);

      expect(output.map((message) => message.text), [
        'abc',
        'Hello from initial',
      ]);
    });

    test('one transfer routes to target and exposes handoff tool', () async {
      late String transferName;
      final initial = _ScriptedAgent(
        name: 'initial',
        onRun: (messages, options) {
          final handoffOptions = options as ChatClientAgentRunOptions;
          transferName = handoffOptions.chatOptions!.tools!.single.name;
          expect(
            transferName,
            startsWith(HandoffWorkflowBuilder.functionPrefix),
          );
          return _functionCall('call1', transferName);
        },
      );
      final target = _ScriptedAgent(
        name: 'target',
        description: 'Target agent',
        onRun: (messages, options) => _assistant('Hello from target'),
      );
      final workflow = AgentWorkflowBuilder.createHandoffBuilderWith(
        initial,
      ).withHandoff(initial, target).build();

      final output = await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'abc'),
      ]);

      expect(output.length, 4);
      expect(output[0].text, 'abc');
      expect(output[1].contents.single, isA<FunctionCallContent>());
      expect(output[2].role, ChatRole.tool);
      expect(output[2].contents.single, isA<FunctionResultContent>());
      expect(output[3].text, 'Hello from target');
      expect(target.runMessages.single.map((message) => message.text), ['abc']);
    });

    test('two transfers filter handoff tool messages from targets', () async {
      String? firstTransfer;
      String? secondTransfer;
      final initial = _ScriptedAgent(
        name: 'initial',
        onRun: (messages, options) {
          firstTransfer = (options as ChatClientAgentRunOptions)
              .chatOptions!
              .tools!
              .single
              .name;
          return AgentResponse(
            message: ChatMessage(
              role: ChatRole.assistant,
              contents: [
                TextContent('Routing to second'),
                FunctionCallContent(callId: 'call1', name: firstTransfer!),
              ],
            ),
          );
        },
      );
      final second = _ScriptedAgent(
        name: 'second',
        description: 'Second agent',
        onRun: (messages, options) {
          secondTransfer = (options as ChatClientAgentRunOptions)
              .chatOptions!
              .tools!
              .single
              .name;
          return AgentResponse(
            message: ChatMessage(
              role: ChatRole.assistant,
              contents: [
                TextContent('Routing to third'),
                FunctionCallContent(callId: 'call2', name: secondTransfer!),
              ],
            ),
          );
        },
      );
      final third = _ScriptedAgent(
        name: 'third',
        description: 'Third agent',
        onRun: (messages, options) => _assistant('Done'),
      );
      final workflow = AgentWorkflowBuilder.createHandoffBuilderWith(
        initial,
      ).withHandoff(initial, second).withHandoff(second, third).build();

      final output = await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'abc'),
      ]);

      expect(output.last.text, 'Done');
      expect(
        second.runMessages.single.any(_containsHandoffFunctionCall),
        isFalse,
      );
      expect(
        third.runMessages.single.any(_containsHandoffFunctionCall),
        isFalse,
      );
      expect(
        third.runMessages.single.any(
          (message) => message.contents.any((c) => c is FunctionResultContent),
        ),
        isFalse,
      );
      expect(
        third.runMessages.single.map((message) => message.text).join('|'),
        contains('Routing to third'),
      );
    });

    test(
      'filtering none preserves handoff calls and results for target',
      () async {
        late String transferName;
        final initial = _ScriptedAgent(
          name: 'initial',
          onRun: (messages, options) {
            transferName = (options as ChatClientAgentRunOptions)
                .chatOptions!
                .tools!
                .single
                .name;
            return _functionCall('call1', transferName);
          },
        );
        final target = _ScriptedAgent(
          name: 'target',
          description: 'Target agent',
          onRun: (messages, options) => _assistant('response'),
        );
        final workflow = AgentWorkflowBuilder.createHandoffBuilderWith(initial)
            .withHandoff(initial, target)
            .withToolCallFilteringBehavior(
              HandoffToolCallFilteringBehavior.none,
            )
            .build();

        await _runForMessages(workflow, [
          ChatMessage.fromText(ChatRole.user, 'hello'),
        ]);

        expect(
          target.runMessages.single.any(_containsHandoffFunctionCall),
          isTrue,
        );
        expect(
          target.runMessages.single.any(
            (message) =>
                message.contents.any((c) => c is FunctionResultContent),
          ),
          isTrue,
        );
      },
    );

    test('filtering all removes non-handoff tool calls too', () async {
      late String transferName;
      final initial = _ScriptedAgent(
        name: 'initial',
        onRun: (messages, options) {
          transferName = (options as ChatClientAgentRunOptions)
              .chatOptions!
              .tools!
              .single
              .name;
          return _functionCall('call1', transferName);
        },
      );
      final target = _ScriptedAgent(
        name: 'target',
        description: 'Target agent',
        onRun: (messages, options) => _assistant('response'),
      );
      final workflow = AgentWorkflowBuilder.createHandoffBuilderWith(initial)
          .withHandoff(initial, target)
          .withToolCallFilteringBehavior(HandoffToolCallFilteringBehavior.all)
          .build();

      await _runForMessages(workflow, [
        ChatMessage.fromText(ChatRole.user, 'Question'),
        ChatMessage(
          role: ChatRole.assistant,
          contents: [FunctionCallContent(callId: 'tool1', name: 'get_weather')],
        ),
        ChatMessage(
          role: ChatRole.tool,
          contents: [FunctionResultContent(callId: 'tool1', result: 'sunny')],
        ),
      ]);

      expect(
        target.runMessages.single.any(
          (message) => message.contents.any((c) => c is FunctionCallContent),
        ),
        isFalse,
      );
      expect(
        target.runMessages.single.any(
          (message) => message.role == ChatRole.tool,
        ),
        isFalse,
      );
    });

    test(
      'return to previous routes later turns directly to specialist',
      () async {
        late String transferName;
        final initial = _ScriptedAgent(
          name: 'initial',
          onRun: (messages, options) {
            transferName = (options as ChatClientAgentRunOptions)
                .chatOptions!
                .tools!
                .single
                .name;
            return _functionCall('call1', transferName);
          },
        );
        final specialist = _ScriptedAgent(
          name: 'specialist',
          description: 'Specialist',
          onRun: (messages, options) =>
              _assistant('specialist:${messages.last.text}'),
        );
        final workflow = AgentWorkflowBuilder.createHandoffBuilderWith(
          initial,
        ).withHandoff(initial, specialist).enableReturnToPrevious().build();

        await _runForMessages(workflow, [
          ChatMessage.fromText(ChatRole.user, 'first'),
        ]);
        final second = await _runForMessages(workflow, [
          ChatMessage.fromText(ChatRole.user, 'second'),
        ]);

        expect(initial.runMessages.length, 1);
        expect(specialist.runMessages.length, 2);
        expect(second.map((message) => message.text), [
          'second',
          'specialist:second',
        ]);
      },
    );
  });

  group('Specialized handoff models', () {
    test('message filter and conversation preserve upstream behavior', () {
      final handoffName = '${HandoffWorkflowBuilder.functionPrefix}1';
      final filter = HandoffMessagesFilter(
        HandoffToolCallFilteringBehavior.handoffOnly,
      );
      final filtered = filter.filterMessages([
        ChatMessage.fromText(ChatRole.user, 'hello'),
        ChatMessage(
          role: ChatRole.assistant,
          contents: [FunctionCallContent(callId: '1', name: handoffName)],
        ),
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(callId: '1', result: 'Transferred.'),
          ],
        ),
        ChatMessage(
          role: ChatRole.assistant,
          contents: [FunctionCallContent(callId: '2', name: 'other')],
        ),
      ]).toList();

      expect(filtered.length, 2);
      expect(filtered.first.text, 'hello');
      expect(
        filtered.last.contents.single,
        isA<FunctionCallContent>().having(
          (content) => content.name,
          'name',
          'other',
        ),
      );

      final conversation = MultiPartyConversation();
      final bookmark = conversation.addMessages(filtered);
      conversation.addMessage(
        ChatMessage.fromText(ChatRole.assistant, 'later'),
      );
      final (newMessages, newBookmark) = conversation.collectNewMessages(
        bookmark,
      );

      expect(newMessages.single.text, 'later');
      expect(newBookmark, 3);
    });

    test('handoff state carries requested and previous agent ids', () {
      const state = HandoffState(
        requestedHandoffTargetAgentId: 'target',
        previousAgentId: 'previous',
        emitEvents: true,
      );

      expect(state.requestedHandoffTargetAgentId, 'target');
      expect(state.previousAgentId, 'previous');
      expect(state.emitEvents, isTrue);
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

AgentResponse _functionCall(String callId, String name) => AgentResponse(
  message: ChatMessage(
    role: ChatRole.assistant,
    contents: [FunctionCallContent(callId: callId, name: name)],
  ),
);

bool _containsHandoffFunctionCall(ChatMessage message) => message.contents.any(
  (content) =>
      content is FunctionCallContent &&
      content.name.startsWith(HandoffWorkflowBuilder.functionPrefix),
);

class _ScriptedAgent extends AIAgent {
  _ScriptedAgent({
    this.agentName,
    this.agentDescription,
    AgentResponse Function(
      List<ChatMessage> messages,
      AgentRunOptions? options,
    )?
    onRun,
    String? name,
    String? description,
  }) : _onRun = onRun,
       _name = name ?? agentName,
       _description = description ?? agentDescription;

  final String? agentName;
  final String? agentDescription;
  final String? _name;
  final String? _description;
  final AgentResponse Function(
    List<ChatMessage> messages,
    AgentRunOptions? options,
  )?
  _onRun;
  final List<List<ChatMessage>> runMessages = <List<ChatMessage>>[];
  final List<AgentRunOptions?> runOptions = <AgentRunOptions?>[];

  @override
  String? get name => _name;

  @override
  String? get description => _description;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _FakeSession();

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
    final captured = List<ChatMessage>.of(messages);
    runMessages.add(captured);
    runOptions.add(options);
    final callback = _onRun;
    if (callback != null) {
      return callback(captured, options);
    }
    return _assistant(name ?? 'agent');
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final response = await runCore(
      messages,
      session: session,
      options: options,
      cancellationToken: cancellationToken,
    );
    for (final update in response.toAgentResponseUpdates()) {
      yield update;
    }
  }
}

class _FakeSession extends AgentSession {
  _FakeSession() : super(AgentSessionStateBag(null));
}
