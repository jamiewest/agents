import 'todo_provider.dart';
import 'todo_item.dart';

/// Options controlling the behavior of [TodoProvider].
class TodoProviderOptions {
  TodoProviderOptions();

  /// Custom instructions provided to the agent for using the todo tools.
  String? instructions;

  /// Whether to suppress injecting the todo list message into the conversation
  /// context.
  bool suppressTodoListMessage = false;

  /// Custom function that builds the todo list message text.
  String Function(List<TodoItem> items)? todoListMessageBuilder;
}
