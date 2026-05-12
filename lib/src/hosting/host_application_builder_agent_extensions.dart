import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/hosting.dart';

import 'agent_hosting_service_collection_extensions.dart';
import 'hosted_agent_builder.dart';

/// Provides extension methods for configuring AI agents in a host application
/// builder.
extension HostApplicationBuilderAgentExtensions on HostApplicationBuilder {
  /// Adds an [AIAgent] to the host application builder with [name] and
  /// optional settings.
  ///
  /// Returns a [HostedAgentBuilder] for further configuration.
  HostedAgentBuilder addAIAgent(
    String name,
    ServiceLifetime lifetime, {
    String? instructions,
    ChatClient? chatClient,
    String? description,
    Object? chatClientServiceKey,
  }) {
    return services.addAIAgent(
      name,
      lifetime,
      instructions: instructions,
      chatClient: chatClient,
      description: description,
      chatClientServiceKey: chatClientServiceKey,
    );
  }
}
