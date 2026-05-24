/// Represents routing state in a handoff workflow.
class HandoffState {
  /// Creates a [HandoffState].
  const HandoffState({
    this.requestedHandoffTargetAgentId,
    this.previousAgentId,
    this.emitEvents,
  });

  /// Gets the requested handoff target agent ID.
  final String? requestedHandoffTargetAgentId;

  /// Gets the previous agent ID.
  final String? previousAgentId;

  /// Gets whether agent response events should be emitted.
  final bool? emitEvents;
}
