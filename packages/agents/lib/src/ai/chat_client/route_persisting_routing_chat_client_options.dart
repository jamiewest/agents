/// Options that control the behavior of a `RoutePersistingRoutingChatClient`.
class RoutePersistingRoutingChatClientOptions {
  /// Creates a [RoutePersistingRoutingChatClientOptions].
  RoutePersistingRoutingChatClientOptions({
    this.defaultRoute,
    this.stateKey,
    this.ownsInnerClients = false,
  });

  /// The route that a new session is initialized with.
  ///
  /// When `null` (the default), the first entry in the routes map supplied to
  /// the `RoutePersistingRoutingChatClient` is used when one exists. The
  /// route is validated only when it is selected, so it does not need to be
  /// registered at construction time.
  String? defaultRoute;

  /// The key used to store the routing state in the session's state bag.
  ///
  /// Defaults to `'RoutePersistingRoutingChatClient'`. Override this when
  /// multiple `RoutePersistingRoutingChatClient` instances need separate
  /// state within the same session.
  String? stateKey;

  /// Whether the `RoutePersistingRoutingChatClient` owns the registered route
  /// clients and disposes them when it is disposed.
  ///
  /// `false` by default, meaning the lifetime of the registered route clients
  /// is managed by the caller. When enabled, each distinct client still
  /// present in the routes map is disposed once when the routing client is
  /// disposed; removing or replacing a route transfers responsibility for the
  /// removed client's lifetime back to the caller.
  bool ownsInnerClients;
}
