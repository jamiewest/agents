import 'workflow_event.dart';

/// Base class for [Executor]-scoped events.
class ExecutorEvent extends WorkflowEvent {
  /// Base class for [Executor]-scoped events.
  const ExecutorEvent(String executorId, Object? data)
    : executorId = executorId;

  /// The identifier of the executor that generated this event.
  String get executorId {
    return executorId;
  }

  @override
  String toString() {
    return this.data != null
        ? '${this.runtimeType.toString()}(Executor = ${this.executorId}, Data: ${this.data.runtimeType} = ${this.data})'
        : '${this.runtimeType.toString()}(Executor = ${this.executorId})';
  }
}
