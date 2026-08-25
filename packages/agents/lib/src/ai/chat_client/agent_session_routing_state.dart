/// Represents the serializable routing state of a
/// `RoutePersistingRoutingChatClient`, stored in the session's
/// `AgentSessionStateBag`.
///
/// This state tracks the route that is currently active for a session, so
/// that the selection survives for the lifetime of the session and across
/// session serialization.
class AgentSessionRoutingState {
  /// Creates an [AgentSessionRoutingState].
  AgentSessionRoutingState({this.activeRoute});

  /// The key of the route that is currently active for this session.
  ///
  /// The value corresponds to a key in the routes map supplied to the
  /// `RoutePersistingRoutingChatClient`. A new session is initialized with
  /// the configured default route.
  String? activeRoute;

  /// Encodes this state to a JSON-compatible map so the session bag can
  /// serialize it.
  Map<String, Object?> toJson() => {
    if (activeRoute != null) 'activeRoute': activeRoute,
  };

  /// Rebuilds the state from a raw JSON-decoded value produced by [toJson].
  static AgentSessionRoutingState fromJson(Object? json) =>
      AgentSessionRoutingState(
        activeRoute: json is Map ? json['activeRoute'] as String? : null,
      );
}
