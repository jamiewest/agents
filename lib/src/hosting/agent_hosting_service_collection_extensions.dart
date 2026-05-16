import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';

import '../abstractions/ai_agent.dart';
import '../ai/chat_client/chat_client_agent.dart';
import 'hosted_agent_builder.dart';

/// Provides extension methods for configuring AI agents in a service
/// collection.
extension AgentHostingServiceCollectionExtensions on ServiceCollection {
  /// Adds an [AIAgent] to the service collection using [name] and optional
  /// settings.
  ///
  /// Returns a [HostedAgentBuilder] for further configuration.
  HostedAgentBuilder addAIAgent(
    String name,
    ServiceLifetime lifetime, {
    String? instructions,
    ChatClient? chatClient,
    Object? chatClientServiceKey,
    String? description,
  }) {
    _registerKeyed<AIAgent>(this, name, (sp, key) {
      final client = chatClient ?? sp.getRequiredService<ChatClient>();
      final tools = sp.getKeyedServices<AITool>(name).toList();
      return ChatClientAgent.withSettings(
        client,
        name: name,
        instructions: instructions,
        description: description,
        tools: tools.isEmpty ? null : tools,
      );
    }, lifetime);
    return _DefaultHostedAgentBuilder(this, name, lifetime);
  }
}

void _registerKeyed<T>(
  ServiceCollection services,
  Object? key,
  KeyedImplementationFactory factory,
  ServiceLifetime lifetime,
) {
  switch (lifetime) {
    case ServiceLifetime.singleton:
      services.addKeyedSingleton<T>(key, factory);
    case ServiceLifetime.scoped:
      services.addKeyedScoped<T>(key, factory);
    case ServiceLifetime.transient:
      services.addKeyedTransient<T>(key, factory);
  }
}

class _DefaultHostedAgentBuilder implements HostedAgentBuilder {
  _DefaultHostedAgentBuilder(this.serviceCollection, this.name, this.lifetime);

  @override
  final ServiceCollection serviceCollection;

  @override
  final String name;

  @override
  final ServiceLifetime lifetime;
}
