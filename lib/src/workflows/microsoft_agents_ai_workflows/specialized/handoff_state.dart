import '../turn_token.dart';

class HandoffState {
  HandoffState(
    TurnToken TurnToken,
    String? RequestedHandoffTargetAgentId, {
    String? PreviousAgentId = null,
  }) : turnToken = TurnToken,
       requestedHandoffTargetAgentId = RequestedHandoffTargetAgentId;

  TurnToken turnToken;

  String? requestedHandoffTargetAgentId;

  String? previousAgentId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HandoffState &&
        turnToken == other.turnToken &&
        requestedHandoffTargetAgentId == other.requestedHandoffTargetAgentId &&
        previousAgentId == other.previousAgentId;
  }

  @override
  int get hashCode {
    return Object.hash(
      turnToken,
      requestedHandoffTargetAgentId,
      previousAgentId,
    );
  }
}
