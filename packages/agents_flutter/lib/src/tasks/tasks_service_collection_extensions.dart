import 'package:extensions_flutter/extensions_flutter.dart';

import '../storage/record_store.dart';
import 'agent_task_store.dart';
import 'task_scheduler_service.dart';

/// Registers the scheduled agent-task subsystem into a [ServiceCollection].
extension TasksServiceCollectionExtensions on ServiceCollection {
  /// Registers the [AgentTaskStore] and the [TaskSchedulerService].
  ///
  /// The scheduler is registered as a plain singleton, not a hosted
  /// service: the host decides when to `start()` it (typically once the
  /// first screen that depends on it mounts) and owns stopping it. Both
  /// registrations are `tryAddSingleton`, so earlier registrations win.
  ServiceCollection addTaskScheduler() {
    tryAddSingleton<AgentTaskStore>(
      (sp) => AgentTaskStore(sp.getRequiredService<RecordStore>()),
    );
    tryAddSingleton<TaskSchedulerService>((sp) => TaskSchedulerService(sp));
    return this;
  }
}
