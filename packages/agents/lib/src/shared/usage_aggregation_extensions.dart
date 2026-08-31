import 'package:extensions/ai.dart';

import '../abstractions/agent_response.dart';

/// Extension for reporting usage aggregated by `UsageAggregator` on the chat
/// response that concludes a run.
extension ChatResponseUsageAggregationExtensions on ChatResponse {
  /// Reports [aggregatedUsage] on this response in place of the usage it
  /// carries, which typically covers only the final service call of a run.
  ///
  /// The supplied response is updated rather than copied, so that a derived
  /// response type returned by an inner client (along with any state it
  /// carries) survives the aggregation. This matches how
  /// [FunctionInvokingChatClient] reports the usage it accumulates across
  /// function-calling iterations. Only the response is mutated:
  /// [aggregatedUsage] is a freshly combined instance, so no [UsageDetails]
  /// owned by an inner client is modified.
  ChatResponse applyAggregatedUsage(UsageDetails? aggregatedUsage) {
    usage = aggregatedUsage;
    return this;
  }
}

/// Extension for reporting usage aggregated by `UsageAggregator` on the agent
/// response that concludes a run.
extension AgentResponseUsageAggregationExtensions on AgentResponse {
  /// Reports [aggregatedUsage] on this response in place of the usage it
  /// carries, which typically covers only the final invocation of a run.
  ///
  /// [messages] gives the messages the response should carry, or `null` to
  /// keep those it already has — used when a run returns a transcript
  /// spanning multiple invocations.
  ///
  /// The supplied response is updated rather than copied, so that a derived
  /// response type returned by an inner agent (along with any state it
  /// carries) survives the aggregation. Only the response is mutated:
  /// [aggregatedUsage] is a freshly combined instance, so no [UsageDetails]
  /// owned by an inner agent is modified.
  AgentResponse applyAggregatedUsage(
    UsageDetails? aggregatedUsage, {
    List<ChatMessage>? messages,
  }) {
    if (messages != null) {
      this.messages = messages;
    }
    usage = aggregatedUsage;
    return this;
  }
}
