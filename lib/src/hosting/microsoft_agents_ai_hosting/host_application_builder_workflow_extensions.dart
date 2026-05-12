import 'package:extensions/dependency_injection.dart';
import 'package:extensions/hosting.dart';

import '../../workflows/microsoft_agents_ai_workflows/workflow.dart';
import 'hosted_workflow_builder.dart';

/// Provides extension methods for configuring AI workflows in a host
/// application builder.
extension HostApplicationBuilderWorkflowExtensions on HostApplicationBuilder {
  /// Registers a workflow using a factory delegate.
  ///
  /// Returns a [HostedWorkflowBuilder] for further configuration.
  HostedWorkflowBuilder addWorkflow(
    String name,
    Workflow Function(ServiceProvider, String) createWorkflowDelegate, {
    ServiceLifetime? lifetime,
  }) {
    final effectiveLifetime = lifetime ?? ServiceLifetime.singleton;
    _registerWorkflow(
      services,
      name,
      createWorkflowDelegate,
      effectiveLifetime,
    );
    return _DefaultHostedWorkflowBuilder(name, this);
  }
}

void _registerWorkflow(
  ServiceCollection services,
  String name,
  Workflow Function(ServiceProvider, String) factory,
  ServiceLifetime lifetime,
) {
  Object keyed(ServiceProvider sp, Object? key) {
    final keyString = key is String ? key : name;
    final workflow = factory(sp, keyString);
    if (workflow.name != null && workflow.name != keyString) {
      throw StateError(
        'The workflow factory returned a workflow with name '
        '"${workflow.name}", but the expected name is "$keyString".',
      );
    }
    return workflow;
  }
  switch (lifetime) {
    case ServiceLifetime.singleton:
      services.addKeyedSingleton<Workflow>(name, keyed);
    case ServiceLifetime.scoped:
      services.addKeyedScoped<Workflow>(name, keyed);
    case ServiceLifetime.transient:
      services.addKeyedTransient<Workflow>(name, keyed);
  }
}

class _DefaultHostedWorkflowBuilder implements HostedWorkflowBuilder {
  _DefaultHostedWorkflowBuilder(this.name, this.hostApplicationBuilder);

  @override
  final String name;

  @override
  final HostApplicationBuilder hostApplicationBuilder;
}
