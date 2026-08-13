import 'package:extensions/system.dart';

/// Provides an abstract base class for resolving keys that isolate resources
/// owned by hosted agents.
///
/// The `Agent` prefix identifies the hosting API domain; it does not mean that
/// agent instances themselves are isolated. The returned key scopes
/// agent-owned resources, such as sessions and A2A tasks, to a logical
/// partition (e.g., user ID, tenant ID, or composite key). Other agent
/// resources, such as memory or retrieval data, can use the same key when they
/// require the same isolation boundary. Derived classes implement the key
/// resolution logic appropriate to their hosting environment.
///
/// When a key is unavailable or cannot be determined, implementations should
/// return `null`. Consuming stores can then enforce strict behavior (throwing
/// an exception) or fall back to unscoped storage based on their
/// configuration.
abstract class AgentIsolationKeyProvider {
  AgentIsolationKeyProvider();

  /// Retrieves the isolation key for agent-owned resources in the current
  /// request or execution context.
  ///
  /// Implementations should extract the key from ambient context (e.g., HTTP
  /// request headers, claims, or environment variables). If the key cannot be
  /// determined, return `null` to allow the caller to decide on strict vs.
  /// pass-through behavior.
  Future<String?> getIsolationKey({CancellationToken? cancellationToken});
}
