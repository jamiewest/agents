import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:pool/pool.dart';

import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../../../abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import 'todo_item.dart';
import 'todo_item_input.dart';
import 'todo_provider_options.dart';
import 'todo_state.dart';

/// An [AIContextProvider] that provides todo management tools and
/// instructions to an agent for tracking work items during long-running
/// complex tasks.
///
/// The [TodoProvider] enables agents to create, complete, remove, and query
/// todo items as part of their planning and execution workflow. Todo state is
/// stored in the session's state bag and persists across agent invocations
/// within the same session. This provider exposes the following tools to the
/// agent:
///
/// * `TodoList_Add` — Add one or more todo items.
/// * `TodoList_Complete` — Mark one or more todo items as complete by ID.
/// * `TodoList_Remove` — Remove one or more todo items by ID.
/// * `TodoList_GetRemaining` — Retrieve only incomplete todo items.
/// * `TodoList_GetAll` — Retrieve all todo items (complete and incomplete).
class TodoProvider extends AIContextProvider implements Disposable {
  /// Creates a [TodoProvider] with optional [options].
  TodoProvider({TodoProviderOptions? options}) {
    _instructions = options?.instructions ?? defaultInstructions;
    _suppressTodoListMessage = options?.suppressTodoListMessage ?? false;
    _todoListMessageBuilder = options?.todoListMessageBuilder;
    _sessionState = ProviderSessionState<TodoState>(
      (_) => TodoState(),
      runtimeType.toString(),
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  static const String defaultInstructions = '''
## Todo Items

You have access to a todo list for tracking work items.
While planning, make sure that you break down complex tasks into manageable todo items and add them to the list.
Ask questions from the user where clarification is needed to create effective todos.
If the user provides feedback on your plan, adjust your todos accordingly by adding new items or removing irrelevant ones.
During execution, use the todo list to keep track of what needs to be done, mark items as complete when finished, and remove any items that are no longer needed.
When a user changes the topic or changes their mind, ensure that you update the todo list accordingly by removing irrelevant items or adding new ones as needed.

Use these tools to manage your tasks:
- Use TodoList_Add to break down complex work into trackable items (supports adding one or many at once).
- Use TodoList_Complete to mark items as done when finished (supports one or many at once).
- Use TodoList_GetRemaining to check what work is still pending.
- Use TodoList_GetAll to review the full list including completed items.
- Use TodoList_Remove to remove items that are no longer needed (supports one or many at once).
''';

  late final ProviderSessionState<TodoState> _sessionState;

  late final String _instructions;

  late final bool _suppressTodoListMessage;

  late final String Function(List<TodoItem> items)? _todoListMessageBuilder;

  final Expando<Pool> _sessionLocks = Expando<Pool>();

  final Pool _nullSessionLock = Pool(1);

  List<String>? _stateKeys;

  @override
  List<String> get stateKeys {
    return _stateKeys ??= [_sessionState.stateKey];
  }

  @override
  void dispose() {
    unawaited(_nullSessionLock.close());
  }

  /// Returns all todo items from the [session] state.
  Future<List<TodoItem>> getAllTodos(AgentSession? session) =>
      getSessionLock(session).withResource(() async {
        final state = _sessionState.getOrInitializeState(session);
        return state.items.toList();
      });

  /// Returns the remaining (incomplete) todo items from the [session] state.
  Future<List<TodoItem>> getRemainingTodos(AgentSession? session) =>
      getSessionLock(session).withResource(() async {
        final state = _sessionState.getOrInitializeState(session);
        return state.items.where((t) => !t.isComplete).toList();
      });

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final aiContext = AIContext()
      ..instructions = _instructions
      ..tools = createTools(context.session);

    if (!_suppressTodoListMessage) {
      final currentItems = await getSessionLock(context.session).withResource(
        () async {
          final state = _sessionState.getOrInitializeState(context.session);
          return state.items.toList();
        },
      );

      final message = _todoListMessageBuilder != null
          ? _todoListMessageBuilder(currentItems)
          : formatTodoListMessage(currentItems);

      aiContext.messages = [ChatMessage.fromText(ChatRole.user, message)];
    }

    return aiContext;
  }

  /// Returns the per-session pool used to serialize all todo operations.
  Pool getSessionLock(AgentSession? session) {
    if (session == null) {
      return _nullSessionLock;
    }

    return _sessionLocks[session] ??= Pool(1);
  }

  List<AITool> createTools(AgentSession? session) {
    return [
      AIFunctionFactory.create(
        name: 'TodoList_Add',
        description:
            'Add one or more todo items. Each item has a title and an optional description. Returns the list of created todo items.',
        parametersSchema: _objectSchema({
          'todos':
              'The todo items to create. Each item has a title and optional description.',
        }),
        callback: (arguments, {cancellationToken}) {
          final todos = _getTodoInputs(arguments, 'todos');
          return getSessionLock(session).withResource(() async {
            final state = _sessionState.getOrInitializeState(session);
            final created = <TodoItem>[];
            for (final input in todos) {
              final item = TodoItem()
                ..id = state.nextId++
                ..title = input.title.trim()
                ..description = input.description?.trim();
              state.items.add(item);
              created.add(item);
            }

            _sessionState.saveState(session, state);
            return created;
          });
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_Complete',
        description:
            'Mark one or more todo items as complete by their IDs. Returns the number of items that were found and marked complete.',
        parametersSchema: _objectSchema({
          'ids': 'The todo item IDs to mark complete.',
        }),
        callback: (arguments, {cancellationToken}) {
          final ids = _getIntList(arguments, 'ids');
          return getSessionLock(session).withResource(() async {
            final state = _sessionState.getOrInitializeState(session);
            final idSet = ids.toSet();
            var completed = 0;
            for (final item in state.items) {
              if (!item.isComplete && idSet.contains(item.id)) {
                item.isComplete = true;
                completed++;
              }
            }

            if (completed > 0) {
              _sessionState.saveState(session, state);
            }

            return completed;
          });
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_Remove',
        description:
            'Remove one or more todo items by their IDs. Returns the number of items that were found and removed.',
        parametersSchema: _objectSchema({
          'ids': 'The todo item IDs to remove.',
        }),
        callback: (arguments, {cancellationToken}) {
          final ids = _getIntList(arguments, 'ids');
          return getSessionLock(session).withResource(() async {
            final state = _sessionState.getOrInitializeState(session);
            final idSet = ids.toSet();
            final beforeCount = state.items.length;
            state.items.removeWhere((t) => idSet.contains(t.id));
            final removed = beforeCount - state.items.length;

            if (removed > 0) {
              _sessionState.saveState(session, state);
            }

            return removed;
          });
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_GetRemaining',
        description: 'Retrieve the list of incomplete todo items.',
        callback: (arguments, {cancellationToken}) =>
            getSessionLock(session).withResource(() async {
              final state = _sessionState.getOrInitializeState(session);
              return state.items.where((t) => !t.isComplete).toList();
            }),
      ),
      AIFunctionFactory.create(
        name: 'TodoList_GetAll',
        description:
            'Retrieve the full list of todo items, both complete and incomplete.',
        callback: (arguments, {cancellationToken}) =>
            getSessionLock(session).withResource(() async {
              final state = _sessionState.getOrInitializeState(session);
              return state.items.toList();
            }),
      ),
    ];
  }

  static String formatTodoListMessage(List<TodoItem> items) {
    if (items.isEmpty) {
      return '### Current todo list\n- none yet';
    }

    final sb = StringBuffer('### Current todo list\n');
    for (final item in items) {
      final status = item.isComplete ? 'done' : 'open';
      sb.write('- ');
      sb.write(item.id);
      sb.write(' [');
      sb.write(status);
      sb.write('] ');
      sb.write(item.title);
      final description = item.description;
      if (description != null && description.trim().isNotEmpty) {
        sb.write(': ');
        sb.write(description);
      }
      sb.writeln();
    }

    return sb.toString().trimRight();
  }

  static List<TodoItemInput> _getTodoInputs(
    AIFunctionArguments arguments,
    String name,
  ) {
    final value = arguments[name];
    if (value is Iterable) {
      return value.map(_toTodoItemInput).toList();
    }
    throw ArgumentError.value(
      value,
      name,
      'Expected a list of todo item inputs.',
    );
  }

  static TodoItemInput _toTodoItemInput(Object? value) {
    if (value is TodoItemInput) {
      return value;
    }

    if (value is Map) {
      final title = value['title'] ?? value['Title'];
      final description = value['description'] ?? value['Description'];
      return TodoItemInput()
        ..title = title is String ? title : ''
        ..description = description is String ? description : null;
    }

    throw ArgumentError.value(value, 'todos', 'Expected a todo item input.');
  }

  static List<int> _getIntList(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value is List<int>) {
      return value;
    }
    if (value is Iterable) {
      return value.map((v) {
        if (v is int) {
          return v;
        }
        if (v is num) {
          return v.toInt();
        }
        throw ArgumentError.value(v, name, 'Expected integer values.');
      }).toList();
    }
    throw ArgumentError.value(value, name, 'Expected a list of integers.');
  }

  static Map<String, dynamic> _objectSchema(Map<String, String> properties) {
    return {
      'type': 'object',
      'properties': {
        for (final entry in properties.entries)
          entry.key: {'description': entry.value},
      },
      'required': properties.keys.toList(),
    };
  }
}
