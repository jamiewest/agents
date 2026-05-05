import 'workflow_event.dart';

/// Event triggered when a workflow executor yields output.
class WorkflowOutputEvent extends WorkflowEvent {
  /// Initializes a new instance of the [WorkflowOutputEvent] class.
  ///
  /// [data] The output data.
  ///
  /// [executorId] The identifier of the executor that yielded this output.
  WorkflowOutputEvent(Object data, String executorId, ) : executorId = executorId {
  }

  /// The unique identifier of the executor that yielded this output.
  final String executorId;

  /// The unique identifier of the executor that yielded this output.
  String get sourceId {
    return this.executorId;
  }

  /// Determines whether the underlying data is of the specified type or a
  /// derived type, and returns it as that type if it is.
  ///
  /// Returns: true if the underlying data is assignable to type T; otherwise,
  /// false.
  ///
  /// [T] The type to compare with the type of the underlying data.
  (bool, T??) isValue<T>() {
    if (this.data is T value) {
      return (true, value);
    }
    return (false, default);
  }

  /// Determines whether the underlying data is of the specified type or a
  /// derived type.
  ///
  /// Returns: true if the underlying data is assignable to type T; otherwise,
  /// false.
  ///
  /// [type] The type to compare with the type of the underlying data.
  bool isType(Type type) {
    return this.data is { } data && type.isInstanceOfType(data);
  }

  /// Attempts to retrieve the underlying data as the specified type.
  ///
  /// Returns: The value of Data as to the target type.
  ///
  /// [T] The type to which to cast.
  T? as<T>() {
    return this.data is T value ? value : default;
  }

  /// Attempts to retrieve the underlying data as the specified type.
  ///
  /// Returns: The value of Data as to the target type.
  ///
  /// [type] The type to which to cast.
  Object? asType(Type type) {
    return this.isType(type) ? this.data : null;
  }
}
