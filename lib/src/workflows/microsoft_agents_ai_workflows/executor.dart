import 'package:extensions/system.dart';

import 'executor_options.dart';
import 'identified.dart';
import 'protocol_builder.dart';
import 'protocol_descriptor.dart';
import 'workflow_context.dart';

/// Base type for workflow executors.
abstract class Executor<TInput, TOutput> implements Identified {
  /// Creates an executor with a stable [id].
  Executor(this.id, {ExecutorOptions? options})
    : options = options ?? const ExecutorOptions();

  /// Gets the executor identifier.
  @override
  final String id;

  /// Gets options describing runtime behavior for this executor.
  final ExecutorOptions options;

  ProtocolDescriptor? _protocol;

  /// Gets the executor protocol descriptor.
  ProtocolDescriptor get protocol => _protocol ??= describeProtocol();

  /// Builds the executor protocol descriptor.
  ProtocolDescriptor describeProtocol() {
    final builder = ProtocolBuilder();
    configureProtocol(builder);
    return builder.build();
  }

  /// Configures the message protocol for this executor.
  void configureProtocol(ProtocolBuilder builder) {
    if (TInput != dynamic && TInput != Object) {
      builder.acceptsMessage<TInput>();
    }
    if (TOutput != dynamic && TOutput != Object) {
      builder.sendsMessage<TOutput>();
    }
  }

  /// Handles an inbound message.
  Future<TOutput> handle(
    TInput message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  });

  /// Gets whether this executor can accept a message of [messageType].
  bool canAccept(Type messageType) => protocol.accepts(messageType);
}
