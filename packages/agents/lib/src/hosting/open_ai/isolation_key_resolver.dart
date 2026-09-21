// Copyright (c) Microsoft. All rights reserved.
//
// Ported from IsolationKeyResolver.cs.

import 'package:extensions/system.dart';

import '../agent_isolation_key_provider.dart';

/// Resolves the isolation key for the caller and composes storage identifiers
/// that are scoped to it.
///
/// This mirrors the scoping performed by `IsolationKeyScopedAgentSessionStore`:
/// a client-supplied identifier is rewritten to
/// `{escapedIsolationKey}::{identifier}` before it reaches storage, so an
/// identifier belonging to another caller resolves into a namespace that does
/// not contain their data.
class IsolationKeyResolver {
  /// Creates a resolver over [keyProvider].
  ///
  /// [keyProvider] is `null` when isolation is not configured. When [strict]
  /// is `true`, a [StateError] is thrown if the key cannot be determined.
  IsolationKeyResolver(this._keyProvider, {required this.strict});

  final AgentIsolationKeyProvider? _keyProvider;

  /// Whether a missing isolation key is an error.
  final bool strict;

  /// Resolves the isolation key for the current caller, or `null` when
  /// isolation is not configured.
  Future<String?> getKey({CancellationToken? cancellationToken}) async {
    final key = _keyProvider == null
        ? null
        : await _keyProvider.getIsolationKey(
            cancellationToken: cancellationToken,
          );

    if (strict && key == null) {
      throw StateError(
        'Agent isolation key is required but was not provided by the '
        'configured AgentIsolationKeyProvider. Ensure the endpoints require '
        'an authenticated caller and that the configured claim is present on '
        'that caller.',
      );
    }

    return key;
  }

  /// Resolves the isolation key and composes a storage identifier scoped to
  /// it, or returns [id] unchanged when isolation is not configured.
  Future<String> scopeIdAsync(
    String id, {
    CancellationToken? cancellationToken,
  }) async => scopeId(id, await getKey(cancellationToken: cancellationToken));

  /// Prefixes [id] with the escaped isolation [key], or returns it unchanged
  /// when no key applies.
  static String scopeId(String id, String? key) =>
      key == null ? id : '${_escapeIsolationKey(key)}::$id';

  /// Whether [scopedId] belongs to the supplied isolation [key].
  static bool isInScope(String scopedId, String? key) =>
      key == null || scopedId.startsWith(_prefix(key));

  /// Strips the isolation key prefix from [scopedId], or returns it unchanged
  /// when the prefix is absent.
  static String unscopeId(String scopedId, String? key) {
    if (key == null) {
      return scopedId;
    }
    final prefix = _prefix(key);
    return scopedId.startsWith(prefix)
        ? scopedId.substring(prefix.length)
        : scopedId;
  }

  static String _prefix(String key) => '${_escapeIsolationKey(key)}::';

  /// Escapes special characters in the isolation key so that scoped
  /// identifiers remain unambiguous. Backslashes are escaped first
  /// (`\` becomes `\\`), then colons (`:` becomes `\:`), matching
  /// `IsolationKeyScopedAgentSessionStore`.
  static String _escapeIsolationKey(String key) =>
      key.replaceAll(r'\', r'\\').replaceAll(':', r'\:');
}
