import 'todo_provider.dart';

/// Represents a single todo item managed by the [TodoProvider].
class TodoItem {
  TodoItem();

  /// Gets or sets the unique identifier for this todo item.
  int id = 0;

  /// Gets or sets the title of this todo item.
  String title = '';

  /// Gets or sets an optional description providing additional details about
  /// this todo item.
  String? description;

  /// Gets or sets a value indicating whether this todo item has been completed.
  bool isComplete = false;
}
