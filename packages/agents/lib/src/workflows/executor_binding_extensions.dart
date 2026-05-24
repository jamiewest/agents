import 'configured_executor_binding.dart';
import 'executor.dart';
import 'executor_binding.dart';
import 'executor_config.dart';
import 'executor_instance_binding.dart';

/// Convenience methods for executor bindings.
extension ExecutorBindingExtensions on ExecutorBinding {
  /// Applies [config] to this executor binding.
  ConfiguredExecutorBinding configured([
    ExecutorConfig config = const ExecutorConfig(),
  ]) => ConfiguredExecutorBinding(this, config);
}

/// Convenience methods for executor instances.
extension ExecutorInstanceBindingExtensions on Executor<dynamic, dynamic> {
  /// Creates a shared instance binding for this executor.
  ExecutorInstanceBinding bindExecutor() => ExecutorInstanceBinding(this);

  /// Creates a configured shared instance binding for this executor.
  ConfiguredExecutorBinding bindConfiguredExecutor([
    ExecutorConfig config = const ExecutorConfig(),
  ]) => ExecutorInstanceBinding(this).configured(config);
}
