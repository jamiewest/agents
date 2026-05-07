/// Configuration options for hosting AI agents as workflow executors.
class AIAgentHostOptions {
  /// Creates [AIAgentHostOptions].
  const AIAgentHostOptions({
    this.emitAgentUpdateEvents,
    this.emitAgentResponseEvents = false,
    this.interceptUserInputRequests = false,
    this.interceptUnterminatedFunctionCalls = false,
    this.reassignOtherAgentsAsUsers = true,
    this.forwardIncomingMessages = true,
  });

  /// Gets whether agent streaming update events should be emitted.
  final bool? emitAgentUpdateEvents;

  /// Gets whether aggregated agent response events should be emitted.
  final bool emitAgentResponseEvents;

  /// Gets whether user input requests should be intercepted.
  final bool interceptUserInputRequests;

  /// Gets whether unterminated function calls should be intercepted.
  final bool interceptUnterminatedFunctionCalls;

  /// Gets whether messages from other agents should become user messages.
  final bool reassignOtherAgentsAsUsers;

  /// Gets whether incoming messages are forwarded before generated messages.
  final bool forwardIncomingMessages;

  /// Creates a copy with selected values changed.
  AIAgentHostOptions copyWith({
    bool? emitAgentUpdateEvents,
    bool? emitAgentResponseEvents,
    bool? interceptUserInputRequests,
    bool? interceptUnterminatedFunctionCalls,
    bool? reassignOtherAgentsAsUsers,
    bool? forwardIncomingMessages,
  }) => AIAgentHostOptions(
    emitAgentUpdateEvents: emitAgentUpdateEvents ?? this.emitAgentUpdateEvents,
    emitAgentResponseEvents:
        emitAgentResponseEvents ?? this.emitAgentResponseEvents,
    interceptUserInputRequests:
        interceptUserInputRequests ?? this.interceptUserInputRequests,
    interceptUnterminatedFunctionCalls:
        interceptUnterminatedFunctionCalls ??
        this.interceptUnterminatedFunctionCalls,
    reassignOtherAgentsAsUsers:
        reassignOtherAgentsAsUsers ?? this.reassignOtherAgentsAsUsers,
    forwardIncomingMessages:
        forwardIncomingMessages ?? this.forwardIncomingMessages,
  );
}
