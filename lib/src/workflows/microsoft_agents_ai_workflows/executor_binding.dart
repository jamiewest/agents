import 'executor.dart';
import 'identified.dart';
import 'protocol_descriptor.dart';

/// Binds an executor identity to a runtime executor instance factory.
abstract class ExecutorBinding implements Identified {
  /// Creates an executor binding.
  const ExecutorBinding(this.id);

  /// Gets the executor identifier.
  @override
  final String id;

  /// Gets whether this binding is a placeholder with no backing factory.
  bool get isPlaceholder => false;

  /// Gets whether this binding reuses a shared executor instance.
  bool get isSharedInstance => false;

  /// Gets whether a shared executor instance supports concurrent execution.
  bool get supportsConcurrentSharedExecution => true;

  /// Gets whether a shared executor instance supports reset between runs.
  bool get supportsResetting => false;

  /// Gets the bound executor protocol.
  Future<ProtocolDescriptor> describeProtocol() async {
    final executor = await createInstance();
    return executor.protocol;
  }

  /// Creates or returns an executor instance.
  Future<Executor<dynamic, dynamic>> createInstance();

  /// Attempts to reset the bound executor.
  Future<bool> tryReset() async => false;
}
