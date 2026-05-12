/// Base type for workflow events.
class WorkflowEvent {
  /// Creates a workflow event.
  const WorkflowEvent({this.data});

  /// Gets event payload data, if any.
  final Object? data;

  /// Gets whether the event payload has exactly runtime type [type].
  bool isType(Type type) => data != null && data.runtimeType == type;

  /// Gets whether the event payload is a [T].
  bool isValue<T>() => data is T;

  /// Gets the event payload as [T].
  T asValue<T>() => data as T;
}
