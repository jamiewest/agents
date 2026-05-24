import 'dart:async';

import 'package:extensions/system.dart';

import 'executor.dart';
import 'protocol_builder.dart';
import 'resettable_executor.dart';
import 'stateful_executor_options.dart';
import 'workflow_context.dart';

/// Base class for executors that maintain state across message handling.
abstract class StatefulExecutor<TState, TInput, TOutput>
    extends Executor<TInput, TOutput>
    implements ResettableExecutor {
  /// Creates a stateful executor.
  StatefulExecutor(super.id, {StatefulExecutorOptions<TState>? options})
    : statefulOptions = options ?? StatefulExecutorOptions<TState>(),
      super(options: options ?? StatefulExecutorOptions<TState>()) {
    state = statefulOptions.createInitialState();
  }

  /// Gets the stateful executor options.
  final StatefulExecutorOptions<TState> statefulOptions;

  /// The current state of this executor.
  TState? state;

  @override
  Future<bool> reset() async {
    state = statefulOptions.createInitialState();
    return true;
  }
}

/// Stateful executor backed by a single callback.
class FunctionStatefulExecutor<TState, TInput, TOutput>
    extends StatefulExecutor<TState, TInput, TOutput> {
  /// Creates a callback-backed stateful executor.
  FunctionStatefulExecutor(
    super.id,
    this.callback, {
    super.options,
    this.configureProtocolCallback,
  });

  /// Gets the callback invoked for each input message.
  final FutureOr<TOutput> Function(
    TInput input,
    WorkflowContext context,
    TState? state,
    CancellationToken cancellationToken,
  )
  callback;

  /// Gets an optional protocol customization callback.
  final void Function(ProtocolBuilder builder)? configureProtocolCallback;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    super.configureProtocol(builder);
    configureProtocolCallback?.call(builder);
  }

  @override
  Future<TOutput> handle(
    TInput message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    token.throwIfCancellationRequested();
    return callback(message, context, state, token);
  }
}
