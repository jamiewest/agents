/// Options for configuring an `IsolationKeyScopedAgentSessionStore`.
class IsolationKeyScopedAgentSessionStoreOptions {
  /// Creates isolation-key scoping options.
  IsolationKeyScopedAgentSessionStoreOptions();

  /// Whether an exception should be thrown when the isolation key cannot be
  /// determined.
  ///
  /// If `true` (default), the store throws a [StateError] when
  /// `SessionIsolationKeyProvider.getSessionIsolationKey` returns `null`.
  ///
  /// If `false`, the conversation ID is passed through unmodified when the
  /// isolation key is absent, allowing unscoped access to the underlying
  /// session store. This mode is suitable for development scenarios or mixed
  /// environments where not all requests have isolation keys.
  bool strict = true;
}
