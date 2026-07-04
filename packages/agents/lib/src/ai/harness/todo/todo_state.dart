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

  /// Encodes this state to a JSON-compatible map so the session bag can
  /// serialize it.
  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'nextId': nextId,
  };

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  static TodoState fromJson(Object? json) {
    final state = TodoState();
    if (json is Map) {
      state.items = [
        for (final entry in json['items'] as List? ?? const [])
          if (entry is Map) TodoItem.fromJson(entry.cast<String, Object?>()),
      ];
      state.nextId = (json['nextId'] as num?)?.toInt() ?? 1;
    }
    return state;
  }
}
