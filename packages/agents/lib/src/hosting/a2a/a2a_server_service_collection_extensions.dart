import 'package:a2a/a2a.dart' show A2AAgentExecutor;
import 'package:extensions/dependency_injection.dart';

import '../../abstractions/ai_agent.dart';
import '../agent_session_store.dart';
import '../ai_host_agent.dart';
import '../hosted_agent_builder.dart';
import '../local/in_memory_agent_session_store.dart';
import 'a2a_agent_handler.dart';
import 'a2a_server_registration_options.dart';
import 'agent_run_mode.dart';

/// A callback that configures [A2AServerRegistrationOptions].
typedef ConfigureA2AServerOptions =
    void Function(A2AServerRegistrationOptions options);

/// Registers A2A server bridges (an [A2AAgentExecutor] per agent) in a
/// [ServiceCollection].
///
/// **Trust model.** The A2A `contextId` arrives from the wire and is treated as
/// a chain-resume identifier — not as an authorization token. The
/// [AgentSessionStore] contract carries no principal/owner dimension, so when a
/// persistent store is registered any caller who knows another caller's
/// `contextId` can resume that caller's persisted thread. This is appropriate
/// for single-user or prototyping scenarios but unsafe for multi-user hosts,
/// which must compose a principal dimension into the lookup key themselves.
extension A2AServerServiceCollectionExtensions on ServiceCollection {
  /// Registers an [A2AAgentExecutor] keyed by an agent name or instance.
  ///
  /// Provide exactly one of [agentName] or [agent]. When [agentName] is given,
  /// the agent is resolved from the container by that key at build time; when
  /// [agent] is given, that instance is used directly and the registration is
  /// keyed by its [AIAgent.name].
  ///
  /// This only registers the bridge. Exposing it over HTTP (for example via the
  /// `a2a` package's request handler and server app) is the host's
  /// responsibility during application startup.
  ServiceCollection addA2AServer({
    String? agentName,
    AIAgent? agent,
    ConfigureA2AServerOptions? configureOptions,
  }) {
    if ((agentName == null) == (agent == null)) {
      throw ArgumentError('Provide exactly one of agentName or agent.');
    }

    final key = agentName ?? _requireName(agent!);
    final options = _buildOptions(configureOptions);

    addKeyedSingleton<A2AAgentExecutor>(key, (sp, _) {
      final resolved = agent ?? sp.getRequiredKeyedService<AIAgent>(key);
      final store =
          sp.getKeyedService<AgentSessionStore>(key) ??
          InMemoryAgentSessionStore();
      final runMode = options?.agentRunMode ?? AgentRunMode.disallowBackground;
      return A2AAgentHandler(AIHostAgent(resolved, store), runMode);
    });

    return this;
  }
}

/// Registers an A2A server bridge for an agent configured through a
/// [HostedAgentBuilder].
extension A2AServerHostedAgentBuilderExtensions on HostedAgentBuilder {
  /// Registers an [A2AAgentExecutor] keyed by this builder's [name].
  ///
  /// See [A2AServerServiceCollectionExtensions] for the trust-model guidance
  /// that applies to multi-user hosts.
  HostedAgentBuilder addA2AServer({
    ConfigureA2AServerOptions? configureOptions,
  }) {
    serviceCollection.addA2AServer(
      agentName: name,
      configureOptions: configureOptions,
    );
    return this;
  }
}

A2AServerRegistrationOptions? _buildOptions(
  ConfigureA2AServerOptions? configureOptions,
) {
  if (configureOptions == null) {
    return null;
  }
  final options = A2AServerRegistrationOptions();
  configureOptions(options);
  return options;
}

String _requireName(AIAgent agent) {
  final name = agent.name;
  if (name == null || name.isEmpty) {
    throw ArgumentError('agent.name must be a non-empty value.');
  }
  return name;
}
