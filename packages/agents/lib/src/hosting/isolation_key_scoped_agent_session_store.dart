import 'package:extensions/system.dart';

import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import 'delegating_agent_session_store.dart';
import 'isolation_key_scoped_agent_session_store_options.dart';
import 'session_isolation_key_provider.dart';

/// A delegating agent session store that scopes session keys by an isolation
/// key provided by a [SessionIsolationKeyProvider], ensuring that sessions
/// are isolated per logical partition (e.g., user, tenant, or composite key).
class IsolationKeyScopedAgentSessionStore extends DelegatingAgentSessionStore {
  /// Creates an [IsolationKeyScopedAgentSessionStore] wrapping [innerStore].
  ///
  /// [keyProvider] retrieves the isolation key for the current context.
  /// [options] configures the store; when `null`, defaults are used.
  IsolationKeyScopedAgentSessionStore(
    super.innerStore,
    SessionIsolationKeyProvider? keyProvider, {
    IsolationKeyScopedAgentSessionStoreOptions? options,
  }) : _keyProvider = keyProvider,
       _strict =
           (options ?? IsolationKeyScopedAgentSessionStoreOptions()).strict;

  final SessionIsolationKeyProvider? _keyProvider;
  final bool _strict;

  @override
  Future<AgentSession> getSession(
    AIAgent agent,
    String conversationId, {
    CancellationToken? cancellationToken,
  }) async {
    final scopedConversationId = await _getScopedConversationId(
      conversationId,
      cancellationToken,
    );
    return innerStore.getSession(
      agent,
      scopedConversationId,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future saveSession(
    AIAgent agent,
    String conversationId,
    AgentSession session, {
    CancellationToken? cancellationToken,
  }) async {
    final scopedConversationId = await _getScopedConversationId(
      conversationId,
      cancellationToken,
    );
    await innerStore.saveSession(
      agent,
      scopedConversationId,
      session,
      cancellationToken: cancellationToken,
    );
  }

  /// Retrieves the isolation key from the provider, throwing in strict mode
  /// when no key is available.
  Future<String?> _getIsolationKey(CancellationToken? cancellationToken) async {
    final key = _keyProvider == null
        ? null
        : await _keyProvider.getSessionIsolationKey(
            cancellationToken: cancellationToken,
          );

    if (_strict && key == null) {
      throw StateError(
        'Session isolation key is required but was not provided by the '
        'configured SessionIsolationKeyProvider.',
      );
    }

    return key;
  }

  /// Escapes special characters in the isolation key so the scoped
  /// conversation ID format `{key}::{conversationId}` stays unambiguous.
  /// Backslashes are escaped first (`\` becomes `\\`), then colons
  /// (`:` becomes `\:`).
  static String _escapeIsolationKey(String key) =>
      key.replaceAll(r'\', r'\\').replaceAll(':', r'\:');

  /// Constructs a scoped conversation ID by prefixing [bareConversationId]
  /// with the escaped isolation key, or returns it unchanged when no key is
  /// available and non-strict mode is enabled.
  Future<String> _getScopedConversationId(
    String bareConversationId,
    CancellationToken? cancellationToken,
  ) async {
    final key = await _getIsolationKey(cancellationToken);
    if (key == null) {
      return bareConversationId;
    }
    return '${_escapeIsolationKey(key)}::$bareConversationId';
  }
}
