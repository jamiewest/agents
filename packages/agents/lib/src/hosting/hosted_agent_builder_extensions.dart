import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';

import 'agent_session_store.dart';
import 'hosted_agent_builder.dart';
import 'local/in_memory_agent_session_store.dart';

/// Provides extension methods for configuring [HostedAgentBuilder].
extension HostedAgentBuilderExtensions on HostedAgentBuilder {
  /// Configures this agent to use an in-memory session store.
  HostedAgentBuilder withInMemorySessionStore() {
    serviceCollection.addKeyedSingletonInstance<AgentSessionStore>(
      name,
      InMemoryAgentSessionStore(),
    );
    return this;
  }

  /// Registers a session store for this agent.
  HostedAgentBuilder withSessionStore({
    AgentSessionStore? store,
    AgentSessionStore Function(ServiceProvider)? createAgentSessionStore,
    ServiceLifetime? lifetime,
  }) {
    if (store != null) {
      serviceCollection.addKeyedSingletonInstance<AgentSessionStore>(
        name,
        store,
      );
    } else if (createAgentSessionStore != null) {
      serviceCollection.addKeyedSingleton<AgentSessionStore>(
        name,
        (sp, key) => createAgentSessionStore(sp),
      );
    }
    return this;
  }

  /// Adds an [AITool] to the agent being configured.
  HostedAgentBuilder withAITool({
    AITool? tool,
    AITool Function(ServiceProvider)? factoryValue,
    ServiceLifetime? lifetime,
  }) {
    if (tool != null) {
      serviceCollection.addKeyedSingletonInstance<AITool>(name, tool);
    } else if (factoryValue != null) {
      serviceCollection.addKeyedSingleton<AITool>(
        name,
        (sp, key) => factoryValue(sp),
      );
    }
    return this;
  }

  /// Adds multiple [AITool] instances to the agent being configured.
  HostedAgentBuilder withAITools(List<AITool> tools) {
    for (final tool in tools) {
      withAITool(tool: tool);
    }
    return this;
  }
}
