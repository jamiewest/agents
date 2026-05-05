import 'package:extensions/system.dart';
import '../../workflows/microsoft_agents_ai_workflows/workflow.dart';

/// Provides a catalog of registered workflows within the hosting environment.
abstract class WorkflowCatalog {
  /// Initializes a new instance of the [WorkflowCatalog] class.
  const WorkflowCatalog();

  /// Asynchronously retrieves all registered workflows from the catalog.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Stream<Workflow> getWorkflows({CancellationToken? cancellationToken});
}
