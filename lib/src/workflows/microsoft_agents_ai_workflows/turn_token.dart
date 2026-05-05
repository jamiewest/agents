/// Sent to an [AIAgent]-based executor to request a response to accumulated
/// [ChatMessage].
///
/// [emitEvents] Whether to raise AgentRunEvents for this executor.
class TurnToken {
  /// Sent to an [AIAgent]-based executor to request a response to accumulated
  /// [ChatMessage].
  ///
  /// [emitEvents] Whether to raise AgentRunEvents for this executor.
  TurnToken({bool? emitEvents = null});

  /// Gets a value indicating whether events are emitted by the receiving
  /// executor. If the value is not set, defaults to the configuration in the
  /// executor.
  bool? get emitEvents {
    return emitEvents;
  }
}
