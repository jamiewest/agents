import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'workflow_context.dart';

/// Provides extension methods for working with [WorkflowContext] instances.
extension WorkflowContextExtensions on WorkflowContext {
  /// Invokes an asynchronous operation that reads, updates, and persists
  /// workflow state associated with the specified key.
  ///
  /// Returns: A ValueTask that represents the asynchronous operation.
  ///
  /// [context] The workflow context used to access and update state.
  ///
  /// [invocation] A delegate that receives the current state, workflow context,
  /// and cancellation token, and returns the updated state asynchronously.
  ///
  /// [key] The key identifying the state to read and update. Cannot be null or
  /// empty.
  ///
  /// [scopeName] An optional scope name that further qualifies the state key.
  /// If null, the default scope is used.
  ///
  /// [cancellationToken] A cancellation token that can be used to cancel the
  /// asynchronous operation.
  ///
  /// [TState] The type of the state Object to read, update, and persist.
  Future invokeWithState<TState>(
    String key,
    String? scopeName,
    CancellationToken cancellationToken, {
    Func3<TState?, WorkflowContext, CancellationToken, Future<TState?>>?
    invocation,
    TState Function()? initialStateFactory,
  }) async {
    var state = await context
        .readStateAsync<TState>(key, scopeName, cancellationToken)
        ;
    state = await invocation(
      state,
      context,
      cancellationToken,
    );
    await context
        .queueStateUpdate(key, state, scopeName, cancellationToken)
        ;
  }

  /// Queues a message to be sent to connected executors. The message will be
  /// sent during the next SuperStep.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [context] The workflow context used to access and update state.
  ///
  /// [message] The message to be sent.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future sendMessage(Object message, {CancellationToken? cancellationToken}) {
    return context.sendMessage(message, null, cancellationToken);
  }
}
