import 'todo_provider.dart';

/// Represents the input for creating a new todo item via the [TodoProvider].
class TodoItemInput {
  TodoItemInput();

  /// Gets or sets the title of the todo item to create.
  String title = '';

  /// Gets or sets an optional description providing additional details about
  /// the todo item.
  String? description;
}
