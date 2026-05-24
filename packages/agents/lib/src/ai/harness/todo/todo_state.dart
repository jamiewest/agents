import '../../../abstractions/agent_session_state_bag.dart';
import 'todo_item.dart';
import 'todo_provider.dart';

/// Represents the state of the todo list managed by the [TodoProvider],
/// stored in the session's [AgentSessionStateBag].
class TodoState {
  TodoState();

  /// Gets the list of todo items.
  List<TodoItem> items = [];

  /// Next ID to assign to a new todo item.
  int nextId = 1;
}
