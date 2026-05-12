import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/harness/sub_agents/sub_agent_runtime_state.dart';
import 'package:agents/src/ai/harness/sub_agents/sub_agents_provider.dart';
import 'package:agents/src/ai/harness/sub_agents/sub_agents_provider_options.dart';

void main() {
  group('SubAgentsProvider constructor', () {
    test('throws when agents collection is empty', () {
      expect(() => SubAgentsProvider(const []), throwsA(isA<ArgumentError>()));
    });

    test('throws when an agent has an empty name', () {
      final agent = TestAgent('', 'desc');

      expect(() => SubAgentsProvider([agent]), throwsA(isA<ArgumentError>()));
    });

    test('throws when duplicate names are provided case-insensitively', () {
      final agent1 = TestAgent('Research', 'Agent 1');
      final agent2 = TestAgent('research', 'Agent 2');

      expect(
        () => SubAgentsProvider([agent1, agent2]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('succeeds with valid agents', () {
      final agent1 = TestAgent('Research', 'Research agent');
      final agent2 = TestAgent('Writer', 'Writer agent');

      final provider = SubAgentsProvider([agent1, agent2]);

      expect(provider, isNotNull);
    });
  });

  group('SubAgentsProvider context', () {
    test('returns tools and instructions', () async {
      final agent = TestAgent('Research', 'Research agent');
      final provider = SubAgentsProvider([agent]);

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, isNotNull);
      expect(result.tools, hasLength(6));
    });

    test('instructions include agent info', () async {
      final agent1 = TestAgent('Research', 'Performs research');
      final agent2 = TestAgent('Writer', 'Writes content');
      final provider = SubAgentsProvider([agent1, agent2]);

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('Research'));
      expect(result.instructions, contains('Performs research'));
      expect(result.instructions, contains('Writer'));
      expect(result.instructions, contains('Writes content'));
    });

    test('custom instructions and agent list builder are used', () async {
      final agent = TestAgent('Research', 'Research agent');
      final provider = SubAgentsProvider(
        [agent],
        options: SubAgentsProviderOptions()
          ..instructions = 'Custom instructions.\n{sub_agents}'
          ..agentListBuilder = (agents) =>
              'Custom list: ${agents.keys.join(", ")}',
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('Custom instructions.'));
      expect(result.instructions, contains('Custom list: Research'));
      expect(result.instructions, isNot(contains('Available sub-agents:')));
    });
  });

  group('SubAgentsProvider tools', () {
    test('start task returns a task ID', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');

      final result = await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Find information about AI',
          'description': 'Research AI topics',
        }),
      );

      expect(result, contains('1'));
      expect(result, contains('started'));

      completion.complete(agentResponseText('done'));
    });

    test('start task with invalid agent name returns an error', () async {
      final agent = TestAgent('Research', 'Research agent');
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');

      final result = await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'NonExistent',
          'input': 'Some input',
          'description': 'Some task',
        }),
      );

      expect(result, contains('Error'));
      expect(result, contains('NonExistent'));
    });

    test('start task assigns sequential IDs', () async {
      final completion1 = Completer<AgentResponse>();
      final completion2 = Completer<AgentResponse>();
      var callCount = 0;
      final agent = TestAgent.withCallback('Research', () {
        callCount++;
        return callCount == 1 ? completion1.future : completion2.future;
      });
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');

      final result1 = await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Task 1',
          'description': 'First task',
        }),
      );
      final result2 = await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Task 2',
          'description': 'Second task',
        }),
      );

      expect(result1, contains('1'));
      expect(result2, contains('2'));

      completion1.complete(agentResponseText('done'));
      completion2.complete(agentResponseText('done'));
    });

    test('wait for first completion returns completed task ID', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Task 1',
          'description': 'First task',
        }),
      );
      completion.complete(agentResponseText('Result 1'));

      final result = await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      expect(result, contains('1'));
      expect(result, contains('finished with status: Completed'));
    });

    test(
      'wait for first completion with empty list returns an error',
      () async {
        final agent = TestAgent('Research', 'Research agent');
        final tools = await createTools(agent);
        final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');

        final result = await waitForFirst.invoke(
          AIFunctionArguments({'taskIds': <int>[]}),
        );

        expect(result, contains('Error'));
      },
    );

    test('get task results returns completed task text', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');
      final getResults = getTool(tools, 'SubAgents_GetTaskResults');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );
      completion.complete(agentResponseText('AI is fascinating!'));
      await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      final result = await getResults.invoke(
        AIFunctionArguments({'taskId': 1}),
      );

      expect(result, contains('AI is fascinating!'));
    });

    test('get task results for running task returns status', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final getResults = getTool(tools, 'SubAgents_GetTaskResults');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );

      final result = await getResults.invoke(
        AIFunctionArguments({'taskId': 1}),
      );

      expect(result, contains('still running'));
      completion.complete(agentResponseText('done'));
    });

    test('get task results for missing task returns an error', () async {
      final agent = TestAgent('Research', 'Research agent');
      final tools = await createTools(agent);
      final getResults = getTool(tools, 'SubAgents_GetTaskResults');

      final result = await getResults.invoke(
        AIFunctionArguments({'taskId': 999}),
      );

      expect(result, contains('Error'));
    });

    test('get task results for failed task returns error text', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');
      final getResults = getTool(tools, 'SubAgents_GetTaskResults');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );
      completion.completeError(StateError('Connection failed'));
      await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      final result = await getResults.invoke(
        AIFunctionArguments({'taskId': 1}),
      );

      expect(result, contains('failed'));
      expect(result, contains('Connection failed'));
    });

    test('get all tasks returns running and completed tasks', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');
      final getAllTasks = getTool(tools, 'SubAgents_GetAllTasks');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research task',
        }),
      );

      var result = await getAllTasks.invoke(AIFunctionArguments());
      expect(result, contains('Research'));
      expect(result, contains('AI research task'));
      expect(result, contains('Running'));

      completion.complete(agentResponseText('done'));
      await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      result = await getAllTasks.invoke(AIFunctionArguments());
      expect(result, contains('Completed'));
    });

    test('get all tasks returns no tasks when empty', () async {
      final agent = TestAgent('Research', 'Research agent');
      final tools = await createTools(agent);
      final getAllTasks = getTool(tools, 'SubAgents_GetAllTasks');

      final result = await getAllTasks.invoke(AIFunctionArguments());

      expect(result, contains('No tasks'));
    });

    test('continue task resumes completed task with new input', () async {
      final completion1 = Completer<AgentResponse>();
      final completion2 = Completer<AgentResponse>();
      var callCount = 0;
      final agent = TestAgent.withCallback('Research', () {
        callCount++;
        return callCount == 1 ? completion1.future : completion2.future;
      });
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');
      final continueTask = getTool(tools, 'SubAgents_ContinueTask');
      final getResults = getTool(tools, 'SubAgents_GetTaskResults');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );
      completion1.complete(agentResponseText('First result'));
      await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      final continueResult = await continueTask.invoke(
        AIFunctionArguments({'taskId': 1, 'text': 'Please elaborate'}),
      );

      expect(continueResult, contains('continued'));

      completion2.complete(agentResponseText('Elaborated result'));
      await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      final result = await getResults.invoke(
        AIFunctionArguments({'taskId': 1}),
      );
      expect(result, contains('Elaborated result'));
    });

    test('continue task on running task returns an error', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final continueTask = getTool(tools, 'SubAgents_ContinueTask');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );

      final result = await continueTask.invoke(
        AIFunctionArguments({'taskId': 1, 'text': 'More input'}),
      );

      expect(result, contains('still running'));
      completion.complete(agentResponseText('done'));
    });

    test('clear completed task removes terminal task', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final waitForFirst = getTool(tools, 'SubAgents_WaitForFirstCompletion');
      final clearTask = getTool(tools, 'SubAgents_ClearCompletedTask');
      final getResults = getTool(tools, 'SubAgents_GetTaskResults');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );
      completion.complete(agentResponseText('Result'));
      await waitForFirst.invoke(
        AIFunctionArguments({
          'taskIds': [1],
        }),
      );

      final clearResult = await clearTask.invoke(
        AIFunctionArguments({'taskId': 1}),
      );

      expect(clearResult, contains('cleared'));

      final getResult = await getResults.invoke(
        AIFunctionArguments({'taskId': 1}),
      );
      expect(getResult, contains('Error'));
    });

    test('clear task on running task returns an error', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final tools = await createTools(agent);
      final startTask = getTool(tools, 'SubAgents_StartTask');
      final clearTask = getTool(tools, 'SubAgents_ClearCompletedTask');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );

      final result = await clearTask.invoke(AIFunctionArguments({'taskId': 1}));

      expect(result, contains('still running'));
      completion.complete(agentResponseText('done'));
    });

    test('lost running task returns lost status', () async {
      final completion = Completer<AgentResponse>();
      final agent = TestAgent.withRunResult('Research', completion.future);
      final provider = SubAgentsProvider([agent]);
      final session = TestSession();
      final context = createInvokingContext(session: session);
      final result = await provider.invoking(context);
      final startTask = getTool(result.tools!, 'SubAgents_StartTask');
      final getResults = getTool(result.tools!, 'SubAgents_GetTaskResults');

      await startTask.invoke(
        AIFunctionArguments({
          'agentName': 'Research',
          'input': 'Research AI',
          'description': 'AI research',
        }),
      );

      final runtimeState = session.stateBag.getValue<SubAgentRuntimeState>(
        provider.stateKeys[1],
      )!;
      runtimeState.inFlightTasks.clear();

      final getResult = await getResults.invoke(
        AIFunctionArguments({'taskId': 1}),
      );

      expect(getResult, contains('lost'));
      completion.complete(agentResponseText('done'));
    });
  });
}

Future<Iterable<AITool>> createTools(TestAgent agent) async {
  final provider = SubAgentsProvider([agent]);
  final result = await provider.invoking(createInvokingContext());
  return result.tools!;
}

AIFunction getTool(Iterable<AITool> tools, String name) {
  return tools.whereType<AIFunction>().firstWhere((tool) => tool.name == name);
}

InvokingContext createInvokingContext({AgentSession? session}) {
  return InvokingContext(
    TestAgent('Parent', 'Parent agent'),
    session ?? TestSession(),
    AIContext(),
  );
}

AgentResponse agentResponseText(String text) {
  return AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, text));
}

class TestSession extends AgentSession {
  TestSession() : super(AgentSessionStateBag(null));
}

class TestAgent extends AIAgent {
  TestAgent(this._name, this._description)
    : _runCallback = (() async => agentResponseText('done'));

  TestAgent.withRunResult(this._name, Future<AgentResponse> result)
    : _description = null,
      _runCallback = (() => result);

  TestAgent.withCallback(this._name, Future<AgentResponse> Function() callback)
    : _description = null,
      _runCallback = callback;

  final String? _name;
  final String? _description;
  final Future<AgentResponse> Function() _runCallback;

  @override
  String? get name => _name;

  @override
  String? get description => _description;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async {
    return TestSession();
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return {};
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async {
    return TestSession();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return _runCallback();
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return const Stream.empty();
  }
}
