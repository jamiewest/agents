import 'executor_binding.dart';

class ConfiguredExecutorBinding extends ExecutorBinding {
  const ConfiguredExecutorBinding(
    Configured<Executor> ConfiguredExecutor,
    Type ExecutorType,
  ) : configuredExecutor = ConfiguredExecutor;

  Configured<Executor> configuredExecutor;

  final bool isSharedInstance = ConfiguredExecutor.Raw is Executor;

  @override
  Future<bool> resetCore() async {
    if (this.configuredExecutor.raw is ResettableExecutor) {
      final resettable = this.configuredExecutor.raw as ResettableExecutor;
      await resettable.resetAsync();
    }
    return false;
  }

  bool get supportsConcurrentSharedExecution {
    return true;
  }

  bool get supportsResetting {
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConfiguredExecutorBinding &&
        configuredExecutor == other.configuredExecutor &&
        isSharedInstance == other.isSharedInstance;
  }

  @override
  int get hashCode {
    return Object.hash(configuredExecutor, isSharedInstance);
  }
}
