import 'package:extensions/system.dart';

import '../workflow_context.dart';
import 'call_result.dart';

/// A function that handles a typed message and returns a [CallResult].
typedef MessageHandlerFn =
    Future<CallResult?> Function(
      Object message,
      WorkflowContext context,
      CancellationToken cancellationToken,
    );

/// A catch-all handler for messages whose exact type has no registered handler.
typedef CatchAllFn =
    Future<CallResult?> Function(
      Object message,
      WorkflowContext context,
      CancellationToken cancellationToken,
    );

/// Dispatches messages to registered type-specific handlers within an executor.
///
/// Handlers are keyed by exact [Type]. If no handler is found for the message's
/// runtime type, [catchAll] is invoked when provided.
final class MessageRouter {
  /// Creates a [MessageRouter].
  MessageRouter({
    Map<Type, MessageHandlerFn>? handlers,
    this.catchAll,
  }) : _handlers = Map<Type, MessageHandlerFn>.unmodifiable(
         handlers ?? const {},
       );

  final Map<Type, MessageHandlerFn> _handlers;

  /// Optional handler invoked when no typed handler matches.
  final CatchAllFn? catchAll;

  /// Returns `true` when there is a catch-all or a handler for [messageType].
  bool canHandle(Type messageType) =>
      catchAll != null || _handlers.containsKey(messageType);

  /// Whether a catch-all handler is registered.
  bool get hasCatchAll => catchAll != null;

  /// The set of explicitly registered input types.
  Set<Type> get incomingTypes => _handlers.keys.toSet();

  /// Routes [message] through the registered handlers.
  ///
  /// Returns `null` when no handler matched and [requireRoute] is `false`.
  /// Throws when [requireRoute] is `true` and no handler matches.
  Future<CallResult?> routeMessageAsync(
    Object message,
    WorkflowContext context, {
    bool requireRoute = false,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    final handler = _handlers[message.runtimeType];
    try {
      if (handler != null) {
        return await handler(message, context, token);
      }
      if (catchAll != null) {
        return await catchAll!(message, context, token);
      }
    } catch (e) {
      return CallResult(executorId: '', error: e);
    }
    if (requireRoute) {
      throw StateError(
        'No handler registered for message type ${message.runtimeType}.',
      );
    }
    return null;
  }
}
