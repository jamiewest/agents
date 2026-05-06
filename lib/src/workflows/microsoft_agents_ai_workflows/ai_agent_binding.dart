import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'ai_agent_host_options.dart';
import 'executor_binding.dart';

/// Represents the workflow binding details for an AI agent, including
/// configuration options for agent hosting behaviour.
///
/// [Agent] The AI agent.
///
/// [Options] The options for configuring the AI agent host.
class AIAgentBinding extends ExecutorBinding {
  /// Represents the workflow binding details for an AI agent, including
  /// configuration options for agent hosting behaviour.
  ///
  /// [Agent] The AI agent.
  ///
  /// [Options] The options for configuring the AI agent host.
  AIAgentBinding({
    AIAgent? Agent,
    AIAgentHostOptions? Options,
    AIAgent? agent,
    bool? emitEvents,
  }) : agent = agent ?? Agent,
       super((agent ?? Agent)?.id ?? '', null, AIAgentBinding);

  /// The AI agent.
  AIAgent? agent;

  /// The options for configuring the AI agent host.
  AIAgentHostOptions? options;

  bool get isSharedInstance {
    return false;
  }

  bool get supportsConcurrentSharedExecution {
    return true;
  }

  bool get supportsResetting {
    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AIAgentBinding &&
        agent == other.agent &&
        options == other.options;
  }

  @override
  int get hashCode {
    return Object.hash(agent, options);
  }
}
