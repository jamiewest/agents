import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_session.dart';
import '../../abstractions/ai_agent.dart';
import '../../abstractions/provider_session_state.dart';
import '../agent_json_utilities.dart';
import 'agent_session_routing_state.dart';
import 'route_persisting_routing_chat_client_options.dart';

/// A [ChatClient] that routes each request to one of several named inner chat
/// clients, based on a route that is persisted in the agent session's
/// `AgentSessionStateBag`.
///
/// This client holds multiple named inner clients (routes) and selects one
/// per request. The route that is active for a session is stored in the
/// session's state bag as an [AgentSessionRoutingState], so the selection
/// survives for the lifetime of the session and across session serialization.
/// Use [setActiveRoute] and [getActiveRoute] to change or inspect the active
/// route for a session.
///
/// Because the conversation history is carried by the agent's session rather
/// than by the routed client, switching route mid-conversation preserves the
/// full history for whichever client handles the next turn.
///
/// All route clients must use client-side conversation history.
/// Service-stored history is isolated to its originating service and cannot
/// be shared when another route handles the next request.
///
/// A new session starts on
/// [RoutePersistingRoutingChatClientOptions.defaultRoute], or on the first
/// entry of the routes map when no default is configured.
///
/// This client resolves the current session from [AIAgent.currentRunContext],
/// which is set automatically when an agent's run methods are called. It must
/// therefore be invoked within an agent run that has a resolved session;
/// invoking it outside of an agent run, or before a session is resolved,
/// throws a [StateError].
///
/// Service discovery is best-effort and route-specific: [getService] forwards
/// to the active route during a run and to the default route otherwise. When
/// routing among undecorated chat clients, middleware that must apply
/// consistently to every route, such as [FunctionInvokingChatClient], should
/// wrap this routing client rather than individual route clients.
/// Applications that register heterogeneous, pre-decorated route clients are
/// responsible for ensuring their middleware stacks are compatible.
///
/// Instances are thread-safe across different sessions as long as [routes] is
/// not modified. Route mutations must only be performed when no requests are
/// in flight. A single session must not be used concurrently, since the
/// per-session routing state assumes only one request per session is in
/// flight at a time.
class RoutePersistingRoutingChatClient implements ChatClient {
  /// Creates a [RoutePersistingRoutingChatClient] from the initial inner
  /// clients in [routes], keyed by route name.
  ///
  /// The entries are copied into [RoutePersistingRoutingChatClient.routes]
  /// and may be modified there after construction. [options] controls routing
  /// behavior; when `null`, defaults are used.
  RoutePersistingRoutingChatClient(
    Map<String, ChatClient> routes, {
    RoutePersistingRoutingChatClientOptions? options,
  }) : routes = Map<String, ChatClient>.of(routes),
       _defaultRoute =
           options?.defaultRoute ?? (routes.isEmpty ? null : routes.keys.first),
       _ownsInnerClients = options?.ownsInnerClients ?? false {
    _sessionState = ProviderSessionState<AgentSessionRoutingState>(
      (_) => AgentSessionRoutingState(activeRoute: _defaultRoute),
      options?.stateKey ?? 'RoutePersistingRoutingChatClient',
      stateRehydrator: AgentSessionRoutingState.fromJson,
      jsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  /// The mutable routes that requests can be routed to, keyed by route name.
  ///
  /// The map is owned by this instance and initially contains a copy of the
  /// entries supplied to the constructor. Adding, replacing, or removing
  /// routes does not modify the original map. Route mutations are not safe
  /// while requests are in flight. Entries are validated only when selected.
  ///
  /// When [RoutePersistingRoutingChatClientOptions.ownsInnerClients] is
  /// `true`, only clients still present in this map when the routing client
  /// is disposed are disposed; removing or replacing an entry transfers
  /// responsibility for that client's lifetime back to the caller.
  final Map<String, ChatClient> routes;

  final String? _defaultRoute;
  final bool _ownsInnerClients;
  late final ProviderSessionState<AgentSessionRoutingState> _sessionState;
  bool _disposed = false;

  /// Gets the route that is currently active for [session].
  String getActiveRoute(AgentSession session) {
    final route =
        _sessionState.getOrInitializeState(session).activeRoute ??
        _defaultRoute;
    if (route == null) {
      throw StateError('No active or default route is available.');
    }
    return route;
  }

  /// Sets the route that is active for [session].
  ///
  /// [route] must be one of the registered routes; otherwise an
  /// [ArgumentError] is thrown.
  void setActiveRoute(AgentSession session, String route) {
    if (routes[route] == null) {
      throw ArgumentError.value(
        route,
        'route',
        'is not registered with a usable chat client.',
      );
    }
    final state = _sessionState.getOrInitializeState(session);
    state.activeRoute = route;
    _sessionState.saveState(session, state);
  }

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) => _getActiveClient(_getRequiredSession()).getResponse(
    messages: messages,
    options: options,
    cancellationToken: cancellationToken,
  );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) => _getActiveClient(_getRequiredSession()).getStreamingResponse(
    messages: messages,
    options: options,
    cancellationToken: cancellationToken,
  );

  @override
  T? getService<T>({Object? key}) {
    if (key == null && this is T) {
      return this as T;
    }

    // Best effort: forward to the client of the session's active route when a
    // run is in progress, otherwise to the default route's client.
    final session = AIAgent.currentRunContext?.session;
    final route = session != null
        ? (_sessionState.getOrInitializeState(session).activeRoute ??
              _defaultRoute)
        : _defaultRoute;

    return route == null ? null : routes[route]?.getService<T>(key: key);
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      if (_ownsInnerClients) {
        final disposedClients = Set<ChatClient>.identity();
        for (final client in routes.values) {
          if (disposedClients.add(client)) {
            client.dispose();
          }
        }
      }
    }
  }

  /// Gets the session of the current agent run, throwing when no run context
  /// or session is available.
  static AgentSession _getRequiredSession() {
    final runContext = AIAgent.currentRunContext;
    if (runContext == null) {
      throw StateError(
        'RoutePersistingRoutingChatClient can only be used within the '
        'context of a running AIAgent. Ensure that the chat client is being '
        'invoked as part of an AIAgent.run or AIAgent.runStreaming call.',
      );
    }
    final session = runContext.session;
    if (session == null) {
      throw StateError(
        'RoutePersistingRoutingChatClient requires a session. Ensure the '
        'agent has a resolved session before invoking the chat client.',
      );
    }
    return session;
  }

  /// Gets the client registered for the session's active route.
  ChatClient _getActiveClient(AgentSession session) {
    final route = getActiveRoute(session);
    final client = routes[route];
    if (client == null) {
      throw StateError(
        "No usable chat client is registered for the active route '$route'.",
      );
    }
    return client;
  }
}
