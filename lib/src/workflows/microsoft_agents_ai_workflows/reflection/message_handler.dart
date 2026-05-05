import 'package:extensions/system.dart';
import '../workflow_context.dart';

/// A message handler interface for handling messages of type `TMessage` and
/// returning a result.
///
/// Remarks: This interface is obsolete. Use the [MessageHandlerAttribute] on
/// methods in a partial class deriving from [Executor] instead.
///
/// [TMessage] The type of message to handle.
///
/// [TResult] The type of result returned after handling the message.
abstract class MessageHandler<TMessage, TResult> {
  /// Handles the incoming message asynchronously.
  ///
  /// Returns: A task that represents the asynchronous operation.
  ///
  /// [message] The message to handle.
  ///
  /// [context] The execution context.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<TResult> handle(
    TMessage message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  });
}

/// A message handler interface for handling messages of type `TMessage`.
///
/// Remarks: This interface is obsolete. Use the [MessageHandlerAttribute] on
/// methods in a partial class deriving from [Executor] instead.
///
/// [TMessage]
abstract class MessageHandler<TMessage> {
  /// Handles the incoming message asynchronously.
  ///
  /// Returns: A task that represents the asynchronous operation.
  ///
  /// [message] The message to handle.
  ///
  /// [context] The execution context.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future handle(
    TMessage message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  });
}
