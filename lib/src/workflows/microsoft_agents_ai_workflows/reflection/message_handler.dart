import 'package:extensions/system.dart';

import '../workflow_context.dart';

/// A callback that handles a single message of type [T].
///
/// Replaces C#'s `[MessageHandler]`-decorated method pattern. Where the C#
/// framework discovers handlers at runtime via attribute scanning and
/// reflection, Dart requires explicit registration through
/// [HandlerRegistry.on].
typedef MessageHandlerCallback<T> = Future<Object?> Function(
  T message,
  WorkflowContext context,
  CancellationToken? cancellationToken,
);
