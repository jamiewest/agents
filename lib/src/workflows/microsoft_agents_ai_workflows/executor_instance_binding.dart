import 'executor.dart';
import 'executor_binding.dart';
import 'resettable_executor.dart';

/// Represents the workflow binding details for a shared executor instance,
/// including configuration options for event emission.
///
/// [ExecutorInstance] The executor instance to bind. Cannot be null.
class ExecutorInstanceBinding extends ExecutorBinding {
  /// Represents the workflow binding details for a shared executor instance,
  /// including configuration options for event emission.
  ///
  /// [ExecutorInstance] The executor instance to bind. Cannot be null.
  ExecutorInstanceBinding(Executor ExecutorInstance)
      : executorInstance = ExecutorInstance,
        super(ExecutorInstance.id, null, ExecutorInstance.runtimeType,
            RawValue: ExecutorInstance);

  /// The executor instance to bind. Cannot be null.
  Executor executorInstance;

  bool get supportsConcurrentSharedExecution {
    return this.executorInstance.isCrossRunShareable;
  }

  bool get supportsResetting {
    return this.executorInstance is IResettableExecutor;
  }

  bool get isSharedInstance {
    return true;
  }

  @override
  Future<bool> resetCore() async {
    if (this.executorInstance is ResettableExecutor) {
      final resettable = this.executorInstance as ResettableExecutor;
      await resettable.resetAsync();
      return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutorInstanceBinding &&
        executorInstance == other.executorInstance;
  }

  @override
  int get hashCode {
    return executorInstance.hashCode;
  }
}
