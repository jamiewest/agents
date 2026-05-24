import 'package:extensions/dependency_injection.dart';

import '../abstractions/ai_agent.dart';
import '../abstractions/message_ai_context_provider.dart';
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
      agent = _agentFactories[i](agent, services);
    }
    return agent;
  }

  /// Adds a decorator factory to the pipeline.
  AIAgentBuilder useFactory(
    AIAgent Function(AIAgent, ServiceProvider) factory,
  ) {
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
    List<MessageAIContextProvider> providers,
  ) {
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
  Object? getServiceFromType(Type type) => null;
}
