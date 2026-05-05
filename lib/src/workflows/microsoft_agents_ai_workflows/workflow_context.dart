import 'package:extensions/system.dart';
import 'executor_options.dart';
import 'workflow_event.dart';
import 'workflow_output_event.dart';

/// Provides services for an [Executor] during the execution of a workflow.
abstract class WorkflowContext {
  /// Adds an event to the workflow's output queue. These events will be raised
  /// to the caller of the workflow at the end of the current SuperStep.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [workflowEvent] The event to be raised.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future addEvent(
    WorkflowEvent workflowEvent, {
    CancellationToken? cancellationToken,
  });

  /// Queues a message to be sent to connected executors. The message will be
  /// sent during the next SuperStep.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [message] The message to be sent.
  ///
  /// [targetId] An optional identifier of the target executor. If null, the
  /// message is sent to all connected executors. If the target executor is not
  /// connected from this executor via an edge, it will still not receive the
  /// message.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future sendMessage(
    Object message,
    String? targetId, {
    CancellationToken? cancellationToken,
  });

  /// Adds an output value to the workflow's output queue. These outputs will be
  /// bubbled the workflow using the [WorkflowOutputEvent]
  ///
  /// Remarks: The type of the output message must match one of the output types
  /// declared by the Executor. By default, the return types of registered
  /// message handlers are considered output types, unless otherwise specified
  /// using [ExecutorOptions].
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [output] The output value to be returned.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future yieldOutput(Object output, {CancellationToken? cancellationToken});

  /// Adds a request to "halt" workflow execution at the end of the current
  /// SuperStep.
  ///
  /// Returns:
  Future requestHalt();

  /// Reads a state value from the workflow's state store. If no scope is
  /// provided, the executor's default scope is used.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [key] The key of the state value.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  ///
  /// [T] The type of the state value.
  Future<T?> readState<T>(
    String key, {
    String? scopeName,
    CancellationToken? cancellationToken,
  });

  /// Reads or initialized a state value from the workflow's state store. If no
  /// scope is provided, the executor's default scope is used.
  ///
  /// Remarks: When initializing the state, the state will be queued as an
  /// update. If multiple initializations are done in the same SuperStep from
  /// different executors, an error will be generated at the end of the
  /// SuperStep.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [key] The key of the state value.
  ///
  /// [initialStateFactory] A factory to initialize the state if the key has no
  /// value associated with it.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  ///
  /// [T] The type of the state value.
  Future<T> readOrInitState<T>(
    String key,
    T Function() initialStateFactory, {
    String? scopeName,
    CancellationToken? cancellationToken,
  });

  /// Asynchronously reads all state keys within the specified scope.
  ///
  /// [scopeName] An optional name that specifies the scope to read. If null,
  /// the default scope is used.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<Set<String>> readStateKeys({
    String? scopeName,
    CancellationToken? cancellationToken,
  });

  /// Asynchronously updates the state of a queue entry identified by the
  /// specified key and optional scope.
  ///
  /// Remarks: Subsequent reads by this executor will result in the new value of
  /// the state. Other executors will only see the new state starting from the
  /// next SuperStep.
  ///
  /// Returns: A ValueTask that represents the asynchronous update operation.
  ///
  /// [key] The unique identifier for the queue entry to update. Cannot be null
  /// or empty.
  ///
  /// [value] The value to set for the queue entry. If null, the entry's state
  /// may be cleared or reset depending on implementation.
  ///
  /// [scopeName] An optional name that specifies the scope to update. If null,
  /// the default scope is used.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  ///
  /// [T] The type of the value to associate with the queue entry.
  Future queueStateUpdate<T>(
    String key,
    T? value, {
    String? scopeName,
    CancellationToken? cancellationToken,
  });

  /// Asynchronously clears all state entries within the specified scope. This
  /// semantically equivalent to retrieving all keys in the scope and deleting
  /// them one-by-one.
  ///
  /// Remarks: Subsequent reads by this executor will not find any entries in
  /// the cleared scope. Other executors will only see the cleared state
  /// starting from the next SuperStep.
  ///
  /// Returns: A ValueTask that represents the asynchronous clear operation.
  ///
  /// [scopeName] An optional name that specifies the scope to clear. If null,
  /// the default scope is used.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future queueClearScope({
    String? scopeName,
    CancellationToken? cancellationToken,
  });

  /// The trace context associated with the current message ato be
  /// processed by the executor, if any.
  Map<String, String>? get traceContext;

  /// Whether the current execution environment support concurrent runs against
  /// the same workflow instance.
  bool get concurrentRunsEnabled;
}
