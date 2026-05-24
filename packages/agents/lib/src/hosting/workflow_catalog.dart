import 'package:extensions/system.dart';
import '../workflows/workflow.dart';

/// Provides a catalog of registered workflows within the hosting environment.
abstract class WorkflowCatalog {
  const WorkflowCatalog();

  /// All registered workflows in the catalog.
  Stream<Workflow> getWorkflows({CancellationToken? cancellationToken});
}
