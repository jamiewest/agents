import 'todo_provider.dart';

/// Represents the input for creating a new todo item via the [TodoProvider].
class TodoItemInput {
  TodoItemInput();

  /// Title of the todo item to create.
  String title = '';

  /// Optional description providing additional details about the todo item.
  String? description;
}
