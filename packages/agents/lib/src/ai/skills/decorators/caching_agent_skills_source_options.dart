import '../agent_skills_source_context.dart';

/// Options for configuring a [CachingAgentSkillsSource].
class CachingAgentSkillsSourceOptions {
  /// Creates caching options.
  CachingAgentSkillsSourceOptions();

  /// Returns the cache isolation key for a skills-source invocation.
  ///
  /// When this delegate is `null`, or when it returns `null`, the skills are
  /// stored in the shared cache bucket. When it returns a non-null string, the
  /// skills are cached under that key.
  ///
  /// The shared cache bucket is used across all invocations of the provider.
  /// If the inner source returns skills that vary by session, user, tenant, or
  /// another security boundary, configure a key that provides the required
  /// isolation or disable caching through
  /// `AgentSkillsProviderBuilder.disableCaching`.
  ///
  /// The isolation key should be low-cardinality and stable. High-cardinality
  /// keys (for example, per-session IDs) can cause the cache to grow without
  /// bound.
  String? Function(AgentSkillsSourceContext context)? cacheIsolationKeySelector;

  /// The interval after which a cached skill list is considered stale and is
  /// refreshed from the inner source on the next request.
  ///
  /// When `null` (the default), cached results never expire and the inner
  /// source is invoked only once per cache key. Set to a positive [Duration] to
  /// re-invoke the inner source once the cached result is older than the
  /// interval. Values of [Duration.zero] or negative durations effectively
  /// disable caching because the cached result is always considered stale.
  Duration? refreshInterval;
}
