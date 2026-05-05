import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';

import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/delegating_ai_agent.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/message_ai_context_provider.dart';
import 'ai_context_provider_decorators/message_ai_context_provider_agent.dart';
import 'anonymous_delegating_ai_agent.dart';

/// Provides a builder for composing a pipeline of [AIAgent] decorators.
class AIAgentBuilder {
  /// Creates an [AIAgentBuilder] with a fixed [innerAgent] or a factory.
  AIAgentBuilder({
    AIAgent? innerAgent,
    AIAgent Function(ServiceProvider)? innerAgentFactory,
  }) : _innerAgentFactory = innerAgentFactory ?? ((_) => innerAgent!);

  final AIAgent Function(ServiceProvider) _innerAgentFactory;

  final List<AIAgent Function(AIAgent, ServiceProvider)> _agentFactories = [];

  /// Builds the complete agent pipeline.
  ///
  /// [services] An optional [ServiceProvider] for DI resolution.
  AIAgent build({ServiceProvider? services}) {
    services ??= _EmptyServiceProvider.instance;
    var agent = _innerAgentFactory(services);
    for (var i = _agentFactories.length - 1; i >= 0; i--) {
      final next = _agentFactories[i](agent, services);
      if (next == null) {
        throw StateError(
          'AIAgentBuilder entry at index $i returned null. '
          'Ensure callbacks passed to use() return non-null AIAgent instances.',
        );
      }
      agent = next;
    }
    return agent;
  }

  /// Adds a decorator factory to the pipeline.
  AIAgentBuilder useFactory(AIAgent Function(AIAgent, ServiceProvider) factory) {
    _agentFactories.add(factory);
    return this;
  }

  /// Adds a simple agent-to-agent decorator to the pipeline.
  AIAgentBuilder use({
    AIAgent Function(AIAgent)? agentFactory,
    SharedAgentRunDelegate? sharedFunc,
    RunAgentDelegate? runFunc,
    RunStreamingAgentDelegate? runStreamingFunc,
  }) {
    if (agentFactory != null) {
      return useFactory((inner, _) => agentFactory(inner));
    }
    return useFactory(
      (inner, _) => AnonymousDelegatingAIAgent(
        inner,
        sharedFunc: sharedFunc,
        runFunc: runFunc,
        runStreamingFunc: runStreamingFunc,
      ),
    );
  }

  /// Wraps the agent with [MessageAIContextProvider] instances.
  AIAgentBuilder useAIContextProviders(
      List<MessageAIContextProvider> providers) {
    return useFactory(
      (inner, _) => MessageAIContextProviderAgent(inner, providers),
    );
  }
}

/// A no-op [ServiceProvider] used when no DI container is provided.
class _EmptyServiceProvider implements ServiceProvider {
  const _EmptyServiceProvider._();

  static const _EmptyServiceProvider instance = _EmptyServiceProvider._();

  @override
  Object? getService(Type serviceType) => null;

  @override
  Object? getServiceFromType(Type type) => null;
}
