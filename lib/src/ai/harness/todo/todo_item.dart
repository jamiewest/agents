import 'todo_provider.dart';

/// Represents a single todo item managed by the [TodoProvider].
class TodoItem {
  TodoItem();

  /// Unique identifier for this todo item.
  int id = 0;

  /// Title of this todo item.
  String title = '';

  /// Optional description providing additional details about this todo item.
  String? description;

  /// Whether this todo item has been completed.
  bool isComplete = false;
}
