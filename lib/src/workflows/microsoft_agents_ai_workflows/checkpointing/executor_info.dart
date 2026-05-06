import '../executor_binding.dart';
import '../executor.dart';
import 'type_id.dart';

class ExecutorInfo {
  ExecutorInfo(TypeId ExecutorType, String ExecutorId)
    : executorType = ExecutorType,
      executorId = ExecutorId;

  TypeId executorType;

  late String executorId;

  bool isMatch({Executor? executor, ExecutorBinding? binding}) {
    if (binding == null) return false;
    return this.executorType.isMatch(binding.executorType) &&
        this.executorId == binding.id;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutorInfo &&
        executorType == other.executorType &&
        executorId == other.executorId;
  }

  @override
  int get hashCode {
    return Object.hash(executorType, executorId);
  }
}
