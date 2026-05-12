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
import 'package:agents/src/ai/harness/todo/todo_item.dart';
import 'package:agents/src/ai/harness/todo/todo_item_input.dart';
import 'package:agents/src/ai/harness/todo/todo_provider.dart';
import 'package:agents/src/ai/harness/todo/todo_provider_options.dart';
import 'package:agents/src/ai/harness/todo/todo_state.dart';

void main() {
  group('TodoProvider context', () {
    test('returns tools and instructions', () async {
      final provider = TodoProvider();

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, isNotNull);
      expect(result.tools, hasLength(5));
    });

    test('custom instructions override default', () async {
      final provider = TodoProvider(
        options: TodoProviderOptions()
          ..instructions = 'Custom todo instructions.',
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, 'Custom todo instructions.');
    });

    test('null options use default instructions', () async {
      final provider = TodoProvider();

      final result = await provider.invoking(createInvokingContext());

      expect(result.instructions, contains('todo list'));
    });
  });

  group('TodoProvider tools', () {
    test('add creates a single item', () async {
      final (tools, state) = await createToolsWithState();
      final addTodos = getTool(tools, 'TodoList_Add');

      final result = await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            TodoItemInput()
              ..title = ' Test todo '
              ..description = ' A test description ',
          ],
        }),
      );

      final created = result as List<TodoItem>;
      expect(created, hasLength(1));
      expect(state.items, hasLength(1));
      expect(state.items[0].id, 1);
      expect(state.items[0].title, 'Test todo');
      expect(state.items[0].description, 'A test description');
      expect(state.items[0].isComplete, isFalse);
    });

    test('add accepts map-shaped input and creates incrementing IDs', () async {
      final (tools, state) = await createToolsWithState();
      final addTodos = getTool(tools, 'TodoList_Add');

      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            {'title': 'First'},
            {'title': 'Second', 'description': null},
            {'Title': 'Third', 'Description': 'With description'},
          ],
        }),
      );

      expect(state.items, hasLength(3));
      expect(state.items.map((t) => t.id), [1, 2, 3]);
      expect(state.items.map((t) => t.title), ['First', 'Second', 'Third']);
      expect(state.items[2].description, 'With description');
    });

    test('complete marks one item complete', () async {
      final (tools, state) = await createToolsWithState();
      final addTodos = getTool(tools, 'TodoList_Add');
      final completeTodos = getTool(tools, 'TodoList_Complete');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [TodoItemInput()..title = 'Test'],
        }),
      );

      final result = await completeTodos.invoke(
        AIFunctionArguments({
          'ids': [1],
        }),
      );

      expect(state.items[0].isComplete, isTrue);
      expect(result, 1);
    });

    test(
      'complete marks multiple items and returns zero for missing IDs',
      () async {
        final (tools, state) = await createToolsWithState();
        final addTodos = getTool(tools, 'TodoList_Add');
        final completeTodos = getTool(tools, 'TodoList_Complete');
        await addTodos.invoke(
          AIFunctionArguments({
            'todos': [
              TodoItemInput()..title = 'First',
              TodoItemInput()..title = 'Second',
              TodoItemInput()..title = 'Third',
            ],
          }),
        );

        final completed = await completeTodos.invoke(
          AIFunctionArguments({
            'ids': [1, 3],
          }),
        );
        final missing = await completeTodos.invoke(
          AIFunctionArguments({
            'ids': [999],
          }),
        );

        expect(state.items[0].isComplete, isTrue);
        expect(state.items[1].isComplete, isFalse);
        expect(state.items[2].isComplete, isTrue);
        expect(completed, 2);
        expect(missing, 0);
      },
    );

    test(
      'remove removes one or many and returns zero for missing IDs',
      () async {
        final (tools, state) = await createToolsWithState();
        final addTodos = getTool(tools, 'TodoList_Add');
        final removeTodos = getTool(tools, 'TodoList_Remove');
        await addTodos.invoke(
          AIFunctionArguments({
            'todos': [
              TodoItemInput()..title = 'First',
              TodoItemInput()..title = 'Second',
              TodoItemInput()..title = 'Third',
            ],
          }),
        );

        final removed = await removeTodos.invoke(
          AIFunctionArguments({
            'ids': [1, 3],
          }),
        );
        final missing = await removeTodos.invoke(
          AIFunctionArguments({
            'ids': [999],
          }),
        );

        expect(removed, 2);
        expect(missing, 0);
        expect(state.items, hasLength(1));
        expect(state.items[0].title, 'Second');
      },
    );

    test('get remaining returns only incomplete items', () async {
      final (tools, _) = await createToolsWithState();
      final addTodos = getTool(tools, 'TodoList_Add');
      final completeTodos = getTool(tools, 'TodoList_Complete');
      final getRemainingTodos = getTool(tools, 'TodoList_GetRemaining');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            TodoItemInput()..title = 'Done',
            TodoItemInput()..title = 'Pending',
          ],
        }),
      );
      await completeTodos.invoke(
        AIFunctionArguments({
          'ids': [1],
        }),
      );

      final result = await getRemainingTodos.invoke(AIFunctionArguments());

      final remaining = result as List<TodoItem>;
      expect(remaining, hasLength(1));
      expect(remaining[0].title, 'Pending');
    });

    test('get all returns complete and incomplete items', () async {
      final (tools, _) = await createToolsWithState();
      final addTodos = getTool(tools, 'TodoList_Add');
      final completeTodos = getTool(tools, 'TodoList_Complete');
      final getAllTodos = getTool(tools, 'TodoList_GetAll');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            TodoItemInput()..title = 'Done',
            TodoItemInput()..title = 'Pending',
          ],
        }),
      );
      await completeTodos.invoke(
        AIFunctionArguments({
          'ids': [1],
        }),
      );

      final result = await getAllTodos.invoke(AIFunctionArguments());

      final all = result as List<TodoItem>;
      expect(all, hasLength(2));
    });
  });

  group('TodoProvider state helpers', () {
    test('state persists in session state bag', () async {
      final provider = TodoProvider();
      final session = TestSession();
      final context = createInvokingContext(session: session);

      final result1 = await provider.invoking(context);
      final addTodos = getTool(result1.tools!, 'TodoList_Add');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [TodoItemInput()..title = 'Persisted'],
        }),
      );

      final result2 = await provider.invoking(context);
      final getAllTodos = getTool(result2.tools!, 'TodoList_GetAll');
      final allResult = await getAllTodos.invoke(AIFunctionArguments());

      final all = allResult as List<TodoItem>;
      expect(all, hasLength(1));
      expect(all[0].title, 'Persisted');
    });

    test('public getAllTodos returns all items', () async {
      final provider = TodoProvider();
      final session = TestSession();
      final result = await provider.invoking(
        createInvokingContext(session: session),
      );
      final addTodos = getTool(result.tools!, 'TodoList_Add');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            TodoItemInput()..title = 'First',
            TodoItemInput()..title = 'Second',
          ],
        }),
      );

      final todos = await provider.getAllTodos(session);

      expect(todos, hasLength(2));
      expect(todos[0].title, 'First');
      expect(todos[1].title, 'Second');
    });

    test('public getRemainingTodos returns only incomplete items', () async {
      final provider = TodoProvider();
      final session = TestSession();
      final result = await provider.invoking(
        createInvokingContext(session: session),
      );
      final addTodos = getTool(result.tools!, 'TodoList_Add');
      final completeTodos = getTool(result.tools!, 'TodoList_Complete');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            TodoItemInput()..title = 'Done',
            TodoItemInput()..title = 'Pending',
          ],
        }),
      );
      await completeTodos.invoke(
        AIFunctionArguments({
          'ids': [1],
        }),
      );

      final remaining = await provider.getRemainingTodos(session);

      expect(remaining, hasLength(1));
      expect(remaining[0].title, 'Pending');
    });

    test('public getAllTodos returns empty for a new session', () async {
      final provider = TodoProvider();
      final session = TestSession();

      final todos = await provider.getAllTodos(session);

      expect(todos, isEmpty);
    });
  });

  group('TodoProvider message injection', () {
    test('injects empty todo message', () async {
      final provider = TodoProvider();

      final result = await provider.invoking(createInvokingContext());

      final messages = result.messages!.toList();
      expect(messages, hasLength(1));
      expect(messages[0].text, contains('none yet'));
      expect(messages[0].text, contains('### Current todo list'));
    });

    test('injects todo list message with statuses and descriptions', () async {
      final provider = TodoProvider();
      final session = TestSession();
      final context = createInvokingContext(session: session);

      final result1 = await provider.invoking(context);
      final addTodos = getTool(result1.tools!, 'TodoList_Add');
      final completeTodos = getTool(result1.tools!, 'TodoList_Complete');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [
            TodoItemInput()..title = 'First',
            TodoItemInput()
              ..title = 'Second'
              ..description = 'Has details',
          ],
        }),
      );
      await completeTodos.invoke(
        AIFunctionArguments({
          'ids': [1],
        }),
      );

      final result2 = await provider.invoking(context);

      final text = result2.messages!.single.text;
      expect(text, contains('### Current todo list'));
      expect(text, contains('[done] First'));
      expect(text, contains('[open] Second'));
      expect(text, contains(': Has details'));
    });

    test('suppression prevents message injection', () async {
      final provider = TodoProvider(
        options: TodoProviderOptions()..suppressTodoListMessage = true,
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.messages, isNull);
    });

    test('custom todo list message builder is used', () async {
      final provider = TodoProvider(
        options: TodoProviderOptions()
          ..todoListMessageBuilder = (items) => 'Custom: ${items.length} items',
      );
      final session = TestSession();
      final context = createInvokingContext(session: session);

      final result1 = await provider.invoking(context);
      final addTodos = getTool(result1.tools!, 'TodoList_Add');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [TodoItemInput()..title = 'Task A'],
        }),
      );

      final result2 = await provider.invoking(context);

      expect(result2.messages!.single.text, 'Custom: 1 items');
    });

    test('suppression wins over custom builder', () async {
      final provider = TodoProvider(
        options: TodoProviderOptions()
          ..suppressTodoListMessage = true
          ..todoListMessageBuilder = (items) => 'Should not appear',
      );

      final result = await provider.invoking(createInvokingContext());

      expect(result.messages, isNull);
    });

    test('builder receives snapshot list', () async {
      List<TodoItem>? capturedList;
      final provider = TodoProvider(
        options: TodoProviderOptions()
          ..todoListMessageBuilder = (items) {
            capturedList = items;
            return 'snapshot test';
          },
      );
      final session = TestSession();
      final context = createInvokingContext(session: session);

      final result1 = await provider.invoking(context);
      final addTodos = getTool(result1.tools!, 'TodoList_Add');
      await addTodos.invoke(
        AIFunctionArguments({
          'todos': [TodoItemInput()..title = 'Original'],
        }),
      );

      await provider.invoking(context);
      capturedList!.clear();

      final allTodos = await provider.getAllTodos(session);
      expect(allTodos, hasLength(1));
      expect(allTodos[0].title, 'Original');
    });
  });

  group('TodoProvider concurrency', () {
    test('concurrent adds produce unique sequential IDs', () async {
      final provider = TodoProvider();
      final session = TestSession();
      final result = await provider.invoking(
        createInvokingContext(session: session),
      );
      final addTodos = getTool(result.tools!, 'TodoList_Add');
      final getAllTodos = getTool(result.tools!, 'TodoList_GetAll');

      await Future.wait(
        List.generate(
          10,
          (i) => addTodos.invoke(
            AIFunctionArguments({
              'todos': [TodoItemInput()..title = 'Item $i'],
            }),
          ),
        ),
      );

      final allResult = await getAllTodos.invoke(AIFunctionArguments());
      final all = allResult as List<TodoItem>;
      final ids = all.map((t) => t.id).toList()..sort();

      expect(all, hasLength(10));
      expect(ids, List.generate(10, (i) => i + 1));
    });

    test(
      'concurrent add and complete operations serialize correctly',
      () async {
        final provider = TodoProvider();
        final session = TestSession();
        final result = await provider.invoking(
          createInvokingContext(session: session),
        );
        final addTodos = getTool(result.tools!, 'TodoList_Add');
        final completeTodos = getTool(result.tools!, 'TodoList_Complete');
        final getAllTodos = getTool(result.tools!, 'TodoList_GetAll');

        await addTodos.invoke(
          AIFunctionArguments({
            'todos': [
              TodoItemInput()..title = 'Existing 1',
              TodoItemInput()..title = 'Existing 2',
              TodoItemInput()..title = 'Existing 3',
            ],
          }),
        );

        await Future.wait([
          addTodos.invoke(
            AIFunctionArguments({
              'todos': [
                TodoItemInput()..title = 'New A',
                TodoItemInput()..title = 'New B',
              ],
            }),
          ),
          addTodos.invoke(
            AIFunctionArguments({
              'todos': [TodoItemInput()..title = 'New C'],
            }),
          ),
          completeTodos.invoke(
            AIFunctionArguments({
              'ids': [1, 2, 3],
            }),
          ),
        ]);

        final allResult = await getAllTodos.invoke(AIFunctionArguments());
        final all = allResult as List<TodoItem>;
        final ids = all.map((t) => t.id).toList()..sort();
        final completedIds = all
            .where((t) => t.isComplete)
            .map((t) => t.id)
            .toSet();

        expect(all, hasLength(6));
        expect(ids.toSet(), hasLength(ids.length));
        expect(ids, List.generate(6, (i) => i + 1));
        expect(completedIds.containsAll([1, 2, 3]), isTrue);
      },
    );
  });
}

Future<(Iterable<AITool>, TodoState)> createToolsWithState() async {
  final provider = TodoProvider();
  final session = TestSession();
  final result = await provider.invoking(
    createInvokingContext(session: session),
  );
  final state = session.stateBag.getValue<TodoState>(provider.stateKeys[0])!;
  return (result.tools!, state);
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
  TestAgent(this._name, this._description);

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
  }) async {
    return agentResponseText('done');
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
