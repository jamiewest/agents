import 'package:extensions/system.dart';

import '../executor.dart';
import '../protocol_builder.dart';
import '../workflow_context.dart';
import 'message_handler.dart';
import 'message_handler_info.dart';
import 'value_task_type_erasure.dart';

/// A registry that collects typed message handlers during
/// [ReflectingExecutor.configureHandlers].
final class HandlerRegistry {
  final Map<Type, MessageHandlerInfo> _handlers = {};

  /// Registers [handler] for messages of type [T].
  ///
  /// If a handler for [T] is already registered, it is replaced.
  void on<T>(MessageHandlerCallback<T> handler) {
    _handlers[T] = MessageHandlerInfo(
      messageType: T,
      handler: ValueTaskTypeErasure.erase(handler),
    );
  }
}

/// Base executor class that dispatches inbound messages to typed handlers.
///
/// Replaces C#'s [ReflectingExecutor], which discovers `[MessageHandler]`
/// methods via runtime reflection. In Dart there is no runtime reflection,
/// so subclasses explicitly register handlers by overriding
/// [configureHandlers] and calling [HandlerRegistry.on].
///
/// Example:
/// ```dart
/// class MyExecutor extends ReflectingExecutor {
///   MyExecutor() : super('my-executor');
///
///   @override
///   void configureHandlers(HandlerRegistry registry) {
///     registry.on<String>(_handleString);
///     registry.on<int>(_handleInt);
///   }
///
///   Future<Object?> _handleString(
///     String msg, WorkflowContext ctx, CancellationToken? ct) async =>
///       'got: $msg';
///
///   Future<Object?> _handleInt(
///     int msg, WorkflowContext ctx, CancellationToken? ct) async =>
///       msg * 2;
/// }
/// ```
abstract class ReflectingExecutor extends Executor<Object, Object?> {
  /// Creates a reflecting executor with a stable [id].
  ///
  /// [configureHandlers] is called immediately so the handler map is ready
  /// before the executor is used.
  ReflectingExecutor(super.id) {
    final registry = HandlerRegistry();
    configureHandlers(registry);
    _handlers = Map.unmodifiable(registry._handlers);
  }

  late final Map<Type, MessageHandlerInfo> _handlers;

  /// The message types this executor can handle.
  Iterable<Type> get handlerTypes => _handlers.keys;

  /// Registers handlers into [registry].
  ///
  /// Called once during construction. Call [HandlerRegistry.on] for each
  /// message type this executor should handle.
  void configureHandlers(HandlerRegistry registry);

  @override
  void configureProtocol(ProtocolBuilder builder) {
    for (final type in _handlers.keys) {
      builder.acceptsMessageType(type);
    }
  }

  /// Dispatches [message] to the registered handler for its runtime type.
  ///
  /// Returns `null` if no handler is registered for the message type.
  @override
  Future<Object?> handle(
    Object message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final info = _handlers[message.runtimeType];
    return info?.handler(message, context, cancellationToken);
  }
}
