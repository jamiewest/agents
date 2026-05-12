import 'package:extensions/system.dart';

import '../workflow_context.dart';
import 'message_handler.dart';

/// Converts a typed [MessageHandlerCallback<T>] to a type-erased handler.
///
/// Maps C#'s [ValueTaskTypeErasure], which coerces [ValueTask<TOutput>]
/// return types to [ValueTask<object?>] so handlers with different output
/// types can be stored and invoked through a uniform interface. In Dart the
/// only coercion needed is a safe downcast of the incoming [Object] to [T].
final class ValueTaskTypeErasure {
  const ValueTaskTypeErasure._();

  /// Wraps [handler] into a form that accepts [Object] and returns
  /// [Future<Object?>].
  static Future<Object?> Function(
    Object message,
    WorkflowContext context,
    CancellationToken? cancellationToken,
  ) erase<T>(MessageHandlerCallback<T> handler) =>
      (msg, ctx, ct) => handler(msg as T, ctx, ct);
}
