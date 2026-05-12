import 'dart:async';

import 'package:extensions/system.dart';

import 'executor.dart';
import 'protocol_builder.dart';
import 'workflow_context.dart';

/// Handles messages by invoking a user-provided Dart callback.
class FunctionExecutor<TInput, TOutput> extends Executor<TInput, TOutput> {
  /// Creates a function executor.
  FunctionExecutor(
    super.id,
    this.callback, {
    super.options,
    this.configureProtocolCallback,
  });

  /// Gets the function invoked for each input message.
  final FutureOr<TOutput> Function(
    TInput input,
    WorkflowContext context,
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
    return callback(message, context, token);
  }
}

/// Handles messages by invoking an action that does not produce output.
class ActionExecutor<TInput> extends FunctionExecutor<TInput, void> {
  /// Creates an action executor.
  ActionExecutor(
    super.id,
    super.callback, {
    super.options,
    super.configureProtocolCallback,
  });
}
