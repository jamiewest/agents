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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (description != null) 'description': description,
    'isComplete': isComplete,
  };

  /// Creates a [TodoItem] from a JSON-decoded map produced by [toJson].
  static TodoItem fromJson(Map<String, Object?> json) => TodoItem()
    ..id = (json['id'] as num?)?.toInt() ?? 0
    ..title = json['title'] as String? ?? ''
    ..description = json['description'] as String?
    ..isComplete = json['isComplete'] as bool? ?? false;
}
