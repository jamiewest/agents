import 'package:extensions/system.dart';

import '../workflow_context.dart';

/// Associates a [messageType] with a type-erased handler callback.
///
/// Maps C#'s [MessageHandlerInfo], which holds a [MethodInfo] and its
/// declared parameter [Type]. Here the handler is pre-wrapped into an
/// [Object]-input / [Future<Object?>]-output form by [ValueTaskTypeErasure],
/// so [ReflectingExecutor] can invoke it uniformly.
final class MessageHandlerInfo {
  /// Creates a message handler info record.
  const MessageHandlerInfo({
    required this.messageType,
    required this.handler,
  });

  /// The message type this handler accepts.
  final Type messageType;

  /// Type-erased handler invokable with any [Object] input.
  final Future<Object?> Function(
    Object message,
    WorkflowContext context,
    CancellationToken? cancellationToken,
  ) handler;
}
