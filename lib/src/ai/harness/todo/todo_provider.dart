import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../../../abstractions/provider_session_state_t_state_.dart';
import '../../../semaphore_slim.dart';
import '../../agent_json_utilities.dart';
import 'todo_item.dart';
import 'todo_item_input.dart';
import 'todo_provider_options.dart';
import 'todo_state.dart';

/// An [AIContextProvider] that provides todo management tools and
/// instructions to an agent for tracking work items during long-running
/// complex tasks.
///
/// Remarks: The [TodoProvider] enables agents to create, complete, remove,
/// and query todo items as part of their planning and execution workflow.
/// Todo state is stored in the session's AgentSessionStateBag and persists
/// across agent invocations within the same session. This provider exposes
/// the following tools to the agent: `TodoList_Add` — Add one or more todo
/// items, each with a title and optional description. `TodoList_Complete` —
/// Mark one or more todo items as complete by their IDs. `TodoList_Remove` —
/// Remove one or more todo items by their IDs. `TodoList_GetRemaining` —
/// Retrieve only incomplete todo items. `TodoList_GetAll` — Retrieve all todo
/// items (complete and incomplete).
class TodoProvider extends AIContextProvider implements Disposable {
  /// Initializes a new instance of the [TodoProvider] class.
  ///
  /// [options] Optional settings that control provider behavior. When `null`,
  /// defaults are used.
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

  final Expando<SemaphoreSlim> _sessionLocks = Expando<SemaphoreSlim>();

  final SemaphoreSlim _nullSessionLock = SemaphoreSlim(1, 1);

  List<String>? _stateKeys;

  @override
  List<String> get stateKeys {
    return _stateKeys ??= [_sessionState.stateKey];
  }

  @override
  void dispose() {
    _nullSessionLock.dispose();
  }

  /// Gets all todo items from the session state.
  ///
  /// Returns: A list of all todo items. The items are live references to
  /// internal state.
  ///
  /// [session] The agent session to read todos from.
  Future<List<TodoItem>> getAllTodos(AgentSession? session) async {
    final sessionLock = getSessionLock(session);
    await sessionLock.waitAsync();
    try {
      final state = _sessionState.getOrInitializeState(session);
      return state.items.toList();
    } finally {
      sessionLock.release();
    }
  }

  /// Gets the remaining (incomplete) todo items from the session state.
  ///
  /// Returns: A list of incomplete todo items. The items are live references to
  /// internal state.
  ///
  /// [session] The agent session to read todos from.
  Future<List<TodoItem>> getRemainingTodos(AgentSession? session) async {
    final sessionLock = getSessionLock(session);
    await sessionLock.waitAsync();
    try {
      final state = _sessionState.getOrInitializeState(session);
      return state.items.where((t) => !t.isComplete).toList();
    } finally {
      sessionLock.release();
    }
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final aiContext = AIContext()
      ..instructions = _instructions
      ..tools = createTools(context.session);

    if (!_suppressTodoListMessage) {
      final sessionLock = getSessionLock(context.session);
      await sessionLock.waitAsync(cancellationToken);
      late final List<TodoItem> currentItems;
      try {
        final state = _sessionState.getOrInitializeState(context.session);
        currentItems = state.items.toList();
      } finally {
        sessionLock.release();
      }

      final message = _todoListMessageBuilder != null
          ? _todoListMessageBuilder(currentItems)
          : formatTodoListMessage(currentItems);

      aiContext.messages = [ChatMessage.fromText(ChatRole.user, message)];
    }

    return aiContext;
  }

  /// Returns the per-session semaphore used to serialize all todo operations.
  SemaphoreSlim getSessionLock(AgentSession? session) {
    if (session == null) {
      return _nullSessionLock;
    }

    return _sessionLocks[session] ??= SemaphoreSlim(1, 1);
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
        callback: (arguments, {cancellationToken}) async {
          final todos = _getTodoInputs(arguments, 'todos');

          final sessionLock = getSessionLock(session);
          await sessionLock.waitAsync(cancellationToken);
          try {
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
          } finally {
            sessionLock.release();
          }
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_Complete',
        description:
            'Mark one or more todo items as complete by their IDs. Returns the number of items that were found and marked complete.',
        parametersSchema: _objectSchema({
          'ids': 'The todo item IDs to mark complete.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final ids = _getIntList(arguments, 'ids');

          final sessionLock = getSessionLock(session);
          await sessionLock.waitAsync(cancellationToken);
          try {
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
          } finally {
            sessionLock.release();
          }
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_Remove',
        description:
            'Remove one or more todo items by their IDs. Returns the number of items that were found and removed.',
        parametersSchema: _objectSchema({
          'ids': 'The todo item IDs to remove.',
        }),
        callback: (arguments, {cancellationToken}) async {
          final ids = _getIntList(arguments, 'ids');

          final sessionLock = getSessionLock(session);
          await sessionLock.waitAsync(cancellationToken);
          try {
            final state = _sessionState.getOrInitializeState(session);
            final idSet = ids.toSet();
            final beforeCount = state.items.length;
            state.items.removeWhere((t) => idSet.contains(t.id));
            final removed = beforeCount - state.items.length;

            if (removed > 0) {
              _sessionState.saveState(session, state);
            }

            return removed;
          } finally {
            sessionLock.release();
          }
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_GetRemaining',
        description: 'Retrieve the list of incomplete todo items.',
        callback: (arguments, {cancellationToken}) async {
          final sessionLock = getSessionLock(session);
          await sessionLock.waitAsync(cancellationToken);
          try {
            final state = _sessionState.getOrInitializeState(session);
            return state.items.where((t) => !t.isComplete).toList();
          } finally {
            sessionLock.release();
          }
        },
      ),
      AIFunctionFactory.create(
        name: 'TodoList_GetAll',
        description:
            'Retrieve the full list of todo items, both complete and incomplete.',
        callback: (arguments, {cancellationToken}) async {
          final sessionLock = getSessionLock(session);
          await sessionLock.waitAsync(cancellationToken);
          try {
            final state = _sessionState.getOrInitializeState(session);
            return state.items.toList();
          } finally {
            sessionLock.release();
          }
        },
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
