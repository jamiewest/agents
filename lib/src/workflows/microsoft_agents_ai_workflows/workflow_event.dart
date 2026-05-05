import 'workflow.dart';

/// Base class for [Workflow]-scoped events.
class WorkflowEvent {
  /// Base class for [Workflow]-scoped events.
  WorkflowEvent({Object? data = null});

  /// Optional payload
  Object? get data {
    return data;
  }

  @override
  String toString() {
    return this.data != null
        ? '${this.runtimeType.toString()}(data: ${this.data.runtimeType} = ${this.data})'
        : '${this.runtimeType.toString()}()';
  }
}
