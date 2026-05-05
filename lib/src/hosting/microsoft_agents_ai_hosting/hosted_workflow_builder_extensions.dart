import 'package:extensions/dependency_injection.dart';
import 'package:extensions/ai.dart';

import 'host_application_builder_agent_extensions.dart';
import 'hosted_agent_builder.dart';
import 'hosted_workflow_builder.dart';

/// Provides extension methods for [HostedWorkflowBuilder] to enable
/// additional workflow configuration scenarios.
extension HostedWorkflowBuilderExtensions on HostedWorkflowBuilder {
  /// Registers the workflow as an [AIAgent] in the dependency injection
  /// container.
  ///
  /// Returns a [HostedAgentBuilder] for further configuration.
  HostedAgentBuilder addAsAIAgent(
    ServiceLifetime lifetime, {
    String? name,
  }) {
    return hostApplicationBuilder.addAIAgent(
      name ?? this.name,
      lifetime,
    );
  }
}
