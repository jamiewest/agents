import 'todo_provider.dart';

/// Options controlling the behavior of [TodoProvider].
class TodoProviderOptions {
  TodoProviderOptions();

  /// Gets or sets custom instructions provided to the agent for using the todo
  /// tools.
  String? instructions;
}
