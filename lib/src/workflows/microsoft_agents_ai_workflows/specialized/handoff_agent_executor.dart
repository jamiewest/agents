import 'package:extensions/ai.dart';

import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

/// Options used by handoff agent executors.
class HandoffAgentExecutorOptions {
  /// Creates [HandoffAgentExecutorOptions].
  HandoffAgentExecutorOptions({
    this.handoffInstructions,
    this.emitAgentResponseEvents = false,
    this.emitAgentResponseUpdateEvents,
  });

  /// Gets instructions added when handoff tools are available.
  String? handoffInstructions;

  /// Gets whether aggregated agent response events should be emitted.
  bool emitAgentResponseEvents;

  /// Gets whether streaming update events should be emitted.
  bool? emitAgentResponseUpdateEvents;
}

/// Utilities for agent executors used by handoff workflows.
class HandoffAgentExecutor {
  const HandoffAgentExecutor._();

  /// Gets the workflow executor ID for [agent].
  static String idFor(AIAgent agent) => agent.name ?? agent.id;

  /// Creates the synthetic result for a successful handoff function call.
  static FunctionResultContent createHandoffResult(String requestCallId) =>
      FunctionResultContent(callId: requestCallId, result: 'Transferred.');
}
