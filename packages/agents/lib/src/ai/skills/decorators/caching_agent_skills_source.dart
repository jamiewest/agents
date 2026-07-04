import 'package:extensions/system.dart';

import '../agent_skill.dart';
import '../agent_skills_source_context.dart';
import 'caching_agent_skills_source_options.dart';
import 'delegating_agent_skills_source.dart';

/// A skill source decorator that caches the result of the inner source's
/// [getSkills] call, returning the cached list on subsequent invocations.
///
/// Concurrent callers are serialized per cache key so that only one underlying
/// fetch runs at a time. Once a fetch succeeds, the result is cached and shared
/// by all subsequent callers.
///
/// When [CachingAgentSkillsSourceOptions.refreshInterval] is set, a cached
/// result is returned only while it is younger than the interval; once it
/// expires, the next caller re-invokes the inner source and replaces the cached
/// result. When the interval is `null`, the cached result never expires.
///
/// The fetch observes the initiating caller's cancellation token. If that
/// caller cancels, the fetch fails and the result is not cached; the next
/// waiting caller starts a fresh fetch. Likewise, a fetch that fails is not
/// cached and subsequent calls will retry.
class CachingAgentSkillsSource extends DelegatingAgentSkillsSource {
  /// Wraps [innerSource], caching its results according to [options].
  CachingAgentSkillsSource(
    super.innerSource, {
    CachingAgentSkillsSourceOptions? options,
  }) : _options = options;

  static const String _sharedCacheKey =
      'CachingAgentSkillsSource-SharedCacheKey';

  final Map<String, _CacheEntry> _cachedEntries = {};
  final CachingAgentSkillsSourceOptions? _options;
  bool _disposed = false;

  @override
  Future<List<AgentSkill>> getSkills(
    AgentSkillsSourceContext context, {
    CancellationToken? cancellationToken,
  }) async {
    _throwIfDisposed();

    final cacheKey =
        _options?.cacheIsolationKeySelector?.call(context) ?? _sharedCacheKey;
    final entry = _cachedEntries.putIfAbsent(cacheKey, _CacheEntry.new);

    final cached = _tryGetFreshResult(entry);
    if (cached != null) {
      return cached;
    }

    // Only one caller fetches at a time for a given cache key; the rest await
    // the in-flight fetch. Dart's single-threaded event loop makes an in-flight
    // future the natural equivalent of the upstream per-key semaphore.
    final inFlight = entry.inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _fetch(entry, context, cancellationToken);
    entry.inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(entry.inFlight, future)) {
        entry.inFlight = null;
      }
    }
  }

  Future<List<AgentSkill>> _fetch(
    _CacheEntry entry,
    AgentSkillsSourceContext context,
    CancellationToken? cancellationToken,
  ) async {
    final result = await innerSource.getSkills(
      context,
      cancellationToken: cancellationToken,
    );
    entry.result = result;
    entry.lastRefreshedUtc = DateTime.now().toUtc();
    return result;
  }

  /// Returns the cached result for [entry] when it exists and is still fresh;
  /// otherwise `null`.
  List<AgentSkill>? _tryGetFreshResult(_CacheEntry entry) {
    final result = entry.result;
    if (result == null) {
      return null;
    }

    final interval = _options?.refreshInterval;
    final lastRefreshed = entry.lastRefreshedUtc;
    if (interval != null &&
        lastRefreshed != null &&
        DateTime.now().toUtc().difference(lastRefreshed) >= interval) {
      return null;
    }

    return result;
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('CachingAgentSkillsSource has been disposed.');
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _cachedEntries.clear();
      super.dispose();
    }
  }
}

/// A single cache slot: the cached result plus the in-flight fetch that
/// serializes concurrent callers for one cache key.
class _CacheEntry {
  List<AgentSkill>? result;
  DateTime? lastRefreshedUtc;
  Future<List<AgentSkill>>? inFlight;
}
