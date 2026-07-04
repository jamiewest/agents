import 'package:extensions/system.dart';

/// Provides an abstract base class for resolving session isolation keys used
/// to scope agent sessions.
///
/// Session isolation keys enable multi-tenant or multi-user scenarios by
/// scoping agent session storage to a specific logical partition (e.g., user
/// ID, tenant ID, or composite key). Derived classes implement the key
/// resolution logic appropriate to their hosting environment.
///
/// When a key is unavailable or cannot be determined, implementations should
/// return `null`. The consuming session store can then enforce strict
/// behavior (throwing an exception) or fall back to unscoped storage based on
/// its configuration.
abstract class SessionIsolationKeyProvider {
  SessionIsolationKeyProvider();

  /// Retrieves the session isolation key for the current request or
  /// execution context.
  ///
  /// Implementations should extract the key from ambient context (e.g., HTTP
  /// request headers, claims, or environment variables). If the key cannot be
  /// determined, return `null` to allow the caller to decide on strict vs.
  /// pass-through behavior.
  Future<String?> getSessionIsolationKey({
    CancellationToken? cancellationToken,
  });
}
