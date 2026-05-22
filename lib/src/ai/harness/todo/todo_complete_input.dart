import 'todo_provider.dart';

/// Input for completing a single todo item via [TodoProvider].
class TodoCompleteInput {
  TodoCompleteInput();

  /// The ID of the todo item to mark as complete.
  int id = 0;

  /// A reason describing how or why this item was completed.
  String reason = '';
}
