import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
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
/// Todo state is stored in the session's [AgentSessionStateBag] and persists
/// across agent invocations within the same session. This provider exposes
/// the following tools to the agent: `TodoList_Add` — Add one or more todo
/// items, each with a title and optional description. `TodoList_Complete` —
/// Mark one or more todo items as complete by their IDs. `TodoList_Remove` —
/// Remove one or more todo items by their IDs. `TodoList_GetRemaining` —
/// Retrieve only incomplete todo items. `TodoList_GetAll` — Retrieve all todo
/// items (complete and incomplete).
class TodoProvider extends AIContextProvider {
  /// Initializes a new instance of the [TodoProvider] class.
  ///
  /// [options] Optional settings that control provider behavior. When `null`,
  /// defaults are used.
  TodoProvider({TodoProviderOptions? options = null}) {
    this._instructions = options?.instructions ?? DefaultInstructions;
    this._sessionState = ProviderSessionState<TodoState>(
            (_) => todoState(),
            this.runtimeType.toString(),
            AgentJsonUtilities.defaultOptions);
  }

  late final ProviderSessionState<TodoState> _sessionState;

  late final String _instructions;

  List<String>? _stateKeys;

  List<String> get stateKeys {
    return this._stateKeys ??= [this._sessionState.stateKey];
  }

  /// Gets all todo items from the session state.
  ///
  /// Returns: A read-only list of all todo items.
  ///
  /// [session] The agent session to read todos from.
  List<TodoItem> getAllTodos(AgentSession? session) {
    return this._sessionState.getOrInitializeState(session).items;
  }

  /// Gets the remaining (incomplete) todo items from the session state.
  ///
  /// Returns: A list of incomplete todo items.
  ///
  /// [session] The agent session to read todos from.
  List<TodoItem> getRemainingTodos(AgentSession? session) {
    return this._sessionState.getOrInitializeState(session).items.where((t) => !t.isComplete).toList();
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, }
  ) {
    var state = this._sessionState.getOrInitializeState(context.session);
    return Future<AIContext>(AIContext());
  }

  List<AITool> createTools(TodoState state, AgentSession? session, ) {
    var serializerOptions = AgentJsonUtilities.defaultOptions;
    return [
            AIFunctionFactory.create(
                (List<TodoItemInput> todos) {
                
                    var created = List<TodoItem>();
                    for (final input in todos)
                    {
                        var item = todoItem();
                        state.items.add(item);
                        created.add(item);
      }

                    this._sessionState.saveState(session, state);
                    return created;
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                (List<int> ids) {
                
                    var idSet = Set<int>(ids);
                    int completed = 0;
                    for (final item in state.items)
                    {
                        if (!item.isComplete && idSet.contains(item.id))
                        {
                            item.isComplete = true;
                            completed++;
        }
      }

                    if (completed > 0)
                    {
                        this._sessionState.saveState(session, state);
      }

                    return completed;
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                (List<int> ids) {
                
                    var idSet = Set<int>(ids);
                    int removed = state.items.removeAll((t) => idSet.contains(t.id));

                    if (removed > 0)
                    {
                        this._sessionState.saveState(session, state);
      }

                    return removed;
                },
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                () => state.items.where((t) => !t.isComplete).toList(),
                AIFunctionFactoryOptions()),

            AIFunctionFactory.create(
                () => state.items,
                AIFunctionFactoryOptions()),
        ];
  }
}
