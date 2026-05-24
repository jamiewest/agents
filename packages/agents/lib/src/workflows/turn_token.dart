/// Sent to an [AIAgent]-based executor to request a response to accumulated
/// chat messages.
class TurnToken {
  /// Creates a [TurnToken] with an optional [emitEvents] override.
  const TurnToken({this.emitEvents});

  /// Whether the receiving executor should emit agent run events.
  ///
  /// If `null`, the executor uses its own default configuration.
  final bool? emitEvents;
}
