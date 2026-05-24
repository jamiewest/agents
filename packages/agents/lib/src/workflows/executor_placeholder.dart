import 'executor.dart';
import 'executor_binding.dart';

/// Placeholder binding used while a workflow is being assembled.
class ExecutorPlaceholder extends ExecutorBinding {
  /// Creates an executor placeholder.
  const ExecutorPlaceholder(super.id);

  @override
  Future<Executor<dynamic, dynamic>> createInstance() {
    throw StateError('Executor placeholder "$id" has not been bound.');
  }
}
