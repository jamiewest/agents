import 'executor.dart';
import 'executor_binding.dart';
import 'executor_config.dart';
import 'protocol_descriptor.dart';

/// Executor binding decorated with configuration metadata.
class ConfiguredExecutorBinding extends ExecutorBinding {
  /// Creates a configured executor binding.
  ConfiguredExecutorBinding(this.innerBinding, this.config)
    : super(config.id ?? innerBinding.id);

  /// Gets the wrapped executor binding.
  final ExecutorBinding innerBinding;

  /// Gets the binding configuration.
  final ExecutorConfig config;

  @override
  bool get isSharedInstance => innerBinding.isSharedInstance;

  @override
  bool get supportsConcurrentSharedExecution =>
      config.options?.supportsConcurrentSharedExecution ??
      innerBinding.supportsConcurrentSharedExecution;

  @override
  bool get supportsResetting =>
      config.options?.supportsResetting ?? innerBinding.supportsResetting;

  @override
  Future<ProtocolDescriptor> describeProtocol() =>
      innerBinding.describeProtocol();

  @override
  Future<Executor<dynamic, dynamic>> createInstance() =>
      innerBinding.createInstance();

  @override
  Future<bool> tryReset() => innerBinding.tryReset();
}
