import '../../func_typedefs.dart';
import 'executor_binding.dart';
import 'executor_options.dart';
import 'workflow.dart';

/// Represents the workflow binding details for a subworkflow, including its
/// instance, identifier, and optional executor options.
///
/// [WorkflowInstance]
///
/// [Id]
///
/// [ExecutorOptions]
class SubworkflowBinding extends ExecutorBinding {
  /// Represents the workflow binding details for a subworkflow, including its
  /// instance, identifier, and optional executor options.
  ///
  /// [WorkflowInstance]
  ///
  /// [Id]
  ///
  /// [ExecutorOptions]
  SubworkflowBinding(
    Workflow WorkflowInstance,
    String Id,
    {ExecutorOptions? ExecutorOptions = null, },
  ) : workflowInstance = WorkflowInstance;

  ///
  Workflow workflowInstance;

  ///
  ExecutorOptions? executorOptions;

  static Func<String, Future<Executor>> createWorkflowExecutorFactory(
    Workflow workflow,
    String id,
    ExecutorOptions? options,
  ) {
    var ownershipToken = new();
    workflow.takeOwnership(ownershipToken, subworkflow: true);
    return InitHostExecutorAsync;
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<Executor> InitHostExecutorAsync(String sessionId)
    //         {
      //             ProtocolDescriptor workflowProtocol = await workflow.DescribeProtocolAsync();
      //
      //             return new WorkflowHostExecutor(id, workflow, workflowProtocol, sessionId, ownershipToken, options);
      //         }
  }

  bool get isSharedInstance {
    return false;
  }

  bool get supportsConcurrentSharedExecution {
    return true;
  }

  bool get supportsResetting {
    return false;
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is SubworkflowBinding &&
    workflowInstance == other.workflowInstance &&
    executorOptions == other.executorOptions; }
  @override
  int get hashCode { return Object.hash(workflowInstance, executorOptions); }
}
