import 'todo_provider.dart';
import 'todo_item.dart';

/// Options controlling the behavior of [TodoProvider].
class TodoProviderOptions {
  TodoProviderOptions();

  /// Gets or sets custom instructions provided to the agent for using the todo
  /// tools.
  String? instructions;

  /// Gets or sets a value indicating whether to suppress injecting the todo
  /// list message into the conversation context.
  bool suppressTodoListMessage = false;

  /// Gets or sets a custom function that builds the todo list message text.
  String Function(List<TodoItem> items)? todoListMessageBuilder;
}
