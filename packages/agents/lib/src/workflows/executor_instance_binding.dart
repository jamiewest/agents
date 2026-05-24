import 'executor.dart';
import 'executor_binding.dart';
import 'resettable_executor.dart';

/// Binds a workflow executor to an existing shared instance.
class ExecutorInstanceBinding extends ExecutorBinding {
  /// Creates an executor instance binding.
  ExecutorInstanceBinding(this.executor) : super(executor.id);

  /// Gets the shared executor instance.
  final Executor<dynamic, dynamic> executor;

  @override
  bool get isSharedInstance => true;

  @override
  bool get supportsConcurrentSharedExecution =>
      executor.options.supportsConcurrentSharedExecution;

  @override
  bool get supportsResetting =>
      executor.options.supportsResetting || executor is ResettableExecutor;

  @override
  Future<Executor<dynamic, dynamic>> createInstance() async => executor;

  @override
  Future<bool> tryReset() async {
    final maybeResettable = executor;
    if (maybeResettable is ResettableExecutor) {
      return (maybeResettable as ResettableExecutor).reset();
    }
    return false;
  }
}
