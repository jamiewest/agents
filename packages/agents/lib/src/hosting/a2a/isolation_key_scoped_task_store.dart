import 'package:a2a/a2a.dart';
import 'package:extensions/system.dart';

import '../agent_isolation_key_provider.dart';

/// A delegating [A2ATaskStore] that scopes task keys by an isolation key
/// provided by an [AgentIsolationKeyProvider], ensuring that tasks are
/// isolated per logical partition (e.g., user, tenant, or composite key).
///
/// This mirrors the isolation pattern of `IsolationKeyScopedAgentSessionStore`
/// but applies it to the A2A task store, preventing cross-tenant task access
/// in multi-tenant deployments.
///
/// Both the store key and the persisted [A2ATask.contextId] are scoped with
/// the isolation key. The [A2ATaskStore] contract keys tasks by
/// [A2ATask.id], so scoping the id is what scopes the store key; scoping the
/// persisted context keeps a task recognizable as belonging to the calling
/// tenant even when it is matched against the task body rather than the store
/// key. Scoped values are stripped again before being returned, so callers
/// only ever observe bare identifiers.
class IsolationKeyScopedTaskStore implements A2ATaskStore {
  /// Creates a store that delegates to [innerStore], scoping identifiers with
  /// the key returned by [keyProvider].
  ///
  /// When [strict] is `true`, a [StateError] is thrown if the isolation key
  /// cannot be determined. When `false`, identifiers are passed through
  /// unmodified.
  IsolationKeyScopedTaskStore(
    this._innerStore,
    AgentIsolationKeyProvider? keyProvider, {
    bool strict = false,
  }) : _keyProvider = keyProvider,
       _strict = strict;

  final A2ATaskStore _innerStore;
  final AgentIsolationKeyProvider? _keyProvider;
  final bool _strict;

  @override
  Future<A2ATask?> load(String taskId) async {
    final key = await _getIsolationKey();
    final task = await _innerStore.load(_scopeId(taskId, key));
    return task == null ? null : _unscopeTask(task, key);
  }

  @override
  Future<void> save(A2ATask data) async {
    final key = await _getIsolationKey();
    await _innerStore.save(_scopeTask(data, key));
  }

  /// Retrieves the isolation key from the provider, throwing in strict mode
  /// when no key is available.
  Future<String?> _getIsolationKey({
    CancellationToken? cancellationToken,
  }) async {
    final key = _keyProvider == null
        ? null
        : await _keyProvider.getIsolationKey(
            cancellationToken: cancellationToken,
          );

    if (_strict && key == null) {
      throw StateError(
        'Agent isolation key is required but was not provided by the '
        'configured AgentIsolationKeyProvider.',
      );
    }

    return key;
  }

  /// Escapes special characters in the isolation key so the scoped identifier
  /// format `{key}::{id}` stays unambiguous. Backslashes are escaped first
  /// (`\` becomes `\\`), then colons (`:` becomes `\:`).
  static String _escapeIsolationKey(String key) =>
      key.replaceAll(r'\', r'\\').replaceAll(':', r'\:');

  /// Prefixes a bare identifier with the escaped isolation key, or returns it
  /// unchanged when no key applies.
  static String _scopeId(String id, String? key) =>
      key == null ? id : '${_escapeIsolationKey(key)}::$id';

  /// Strips the isolation key prefix from a scoped identifier, or returns it
  /// unchanged when the prefix is absent.
  static String _unscopeId(String scopedId, String? key) {
    if (key == null) {
      return scopedId;
    }
    final prefix = '${_escapeIsolationKey(key)}::';
    return scopedId.startsWith(prefix)
        ? scopedId.substring(prefix.length)
        : scopedId;
  }

  /// Returns a copy of [task] whose id and context id are scoped by [key].
  ///
  /// The task is copied rather than mutated because the A2A server reuses it
  /// for live event notification after persisting; mutating it would surface
  /// the scoped identifiers on the wire.
  static A2ATask _scopeTask(A2ATask task, String? key) {
    if (key == null) {
      return task;
    }
    return task.clone()
      ..id = _scopeId(task.id, key)
      ..contextId = _scopeId(task.contextId, key);
  }

  /// Returns a copy of [task] whose id and context id have the isolation key
  /// removed.
  static A2ATask _unscopeTask(A2ATask task, String? key) {
    if (key == null) {
      return task;
    }
    return task.clone()
      ..id = _unscopeId(task.id, key)
      ..contextId = _unscopeId(task.contextId, key);
  }
}
