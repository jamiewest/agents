// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../configured_agents/configured_agents_manager.dart';
import '../configured_agents/storage/key_value_store.dart';
import 'pairing_payload.dart';
import 'package:extensions_flutter/extensions_flutter.dart';
import 'package:flutter/foundation.dart';

import 'host/a2a_host_service.dart';

/// Which agents are offered to paired devices over the network, and the host
/// that serves them.
///
/// Sharing is a property of an agent, so it is toggled on that agent's page
/// rather than on a screen of its own; this holds the resulting set and keeps
/// the A2A host in step with it. The host runs while at least one agent is
/// shared and stops when the last one is turned off, so "is anything shared"
/// and "is the server up" can never disagree.
///
/// Which agent is shared cannot live in `AgentAccessConfig` — that model
/// belongs to the agents_flutter package, which knows nothing about this
/// app's host — so it is stored here, keyed by agent id, the same way
/// `InventoryAccessSettings` stores its per-agent opt-in.
class NetworkSharingSettings extends ChangeNotifier {
  /// Creates a [NetworkSharingSettings] over the app's services.
  NetworkSharingSettings(this._services);

  static const String _prefix = 'agents_app.network_sharing.';

  final ServiceProvider _services;
  final Set<String> _shared = {};

  A2AHostService? _host;
  String? _error;
  bool _busy = false;
  bool _loopbackOnly = false;

  /// Whether this platform can serve agents at all. Browsers cannot open
  /// server sockets, so the whole feature is hidden there.
  bool get isSupported => !kIsWeb;

  /// Whether the host is currently serving.
  bool get isRunning => _host?.isRunning ?? false;

  /// The bound port, when serving.
  int? get port => _host?.port;

  /// The running host, when serving.
  ///
  /// Exposed so an app can publish it through another transport — an onion
  /// service, say — and issue offers advertising that address instead of the
  /// LAN one.
  A2AHostService? get host => _host;

  /// Whether the host binds loopback only, for peers that reach it through a
  /// local forward rather than across the network.
  bool get loopbackOnly => _loopbackOnly;

  /// Rebinds the host to loopback only, or back to the network.
  ///
  /// Awaitable because the socket is rebound: a caller that reads [port]
  /// straight after would otherwise see the old port, or none at all. A no-op
  /// when the value is unchanged, since rebinding drops connected peers.
  Future<void> setLoopbackOnly(bool value) async {
    if (value == _loopbackOnly) return;
    _loopbackOnly = value;
    if (_shared.isNotEmpty) await _restart();
  }

  /// The last failure to start, stop, or re-route the host, if any.
  String? get error => _error;

  /// Whether a start/stop is in flight, so the UI can disable its controls.
  bool get busy => _busy;

  /// The number of agents currently shared.
  int get sharedCount => _shared.length;

  /// Whether the agent with [agentId] is offered to paired devices.
  bool isShared(String agentId) => _shared.contains(agentId);

  /// Loads the persisted set and brings the host back up if anything is
  /// shared.
  ///
  /// A switch left on has to mean the agent is actually reachable — leaving
  /// the host down until the next toggle would show sharing that is not
  /// happening. Turning every agent off is what stops the server for good.
  ///
  /// The set is read before returning, so the switches render correctly; the
  /// host comes up in the background, since binding a socket and building
  /// every shared agent (which can mean loading a local model) must not hold
  /// up the first frame.
  Future<void> load() async {
    _shared.clear();
    for (final key in await _services.getRequiredService<KeyValueStore>().keys(
      prefix: _prefix,
    )) {
      _shared.add(key.substring(_prefix.length));
    }
    notifyListeners();
    if (_shared.isNotEmpty) unawaited(_apply());
  }

  /// Shares or stops sharing the agent with [agentId], bringing the host up
  /// or down as the set becomes non-empty or empty.
  Future<void> setShared(String agentId, bool shared) async {
    final keyValueStore = _services.getRequiredService<KeyValueStore>();
    if (shared) {
      _shared.add(agentId);
      await keyValueStore.write('$_prefix$agentId', 'true');
    } else {
      _shared.remove(agentId);
      await keyValueStore.delete('$_prefix$agentId');
    }
    await _apply();
  }

  /// Creates a single-use pairing offer for the QR/paste flow.
  ///
  /// Throws when nothing is shared yet, since there is no server to pair
  /// with. The returned token must never be logged or put in model context.
  /// [advertisedHost] and [advertisedPort] override where the offer points,
  /// for hosts reached through a forward rather than directly.
  Future<PairingPayload> createPairingOffer({
    String? advertisedHost,
    int? advertisedPort,
  }) async {
    final host = _host;
    if (host == null || !host.isRunning) {
      throw StateError('Share an agent before creating a pairing code.');
    }
    return host.createPairingOffer(
      advertisedHost: advertisedHost,
      advertisedPort: advertisedPort,
    );
  }

  /// Forgets shared ids that are not in [existingAgentIds].
  Future<void> _prune(Set<String> existingAgentIds) async {
    final stale = _shared.difference(existingAgentIds);
    if (stale.isEmpty) return;
    final keyValueStore = _services.getRequiredService<KeyValueStore>();
    for (final agentId in stale) {
      _shared.remove(agentId);
      await keyValueStore.delete('$_prefix$agentId');
    }
  }

  /// Rebinds the host, so a changed bind address takes effect.
  Future<void> _restart() async {
    await _host?.stop();
    await _apply();
  }

  /// Rebuilds the host's routing table from the shared set.
  Future<void> _apply() async {
    if (!isSupported) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final agents = await _services
          .getRequiredService<ConfiguredAgentsManager>()
          .agents
          .listAgents();
      final shared = [
        for (final agent in agents)
          if (_shared.contains(agent.id)) agent,
      ];
      // A deleted agent must stop being served. Its opt-in outlives it in
      // storage — nothing deletes the key when the agent goes — so drop
      // whatever no longer resolves before the routing table is rebuilt
      // from the set.
      await _prune(agents.map((agent) => agent.id).toSet());
      if (shared.isEmpty) {
        await _host?.stop();
      } else {
        final host = _host ??= A2AHostService(_services);
        if (host.isRunning) {
          await host.setSharedAgents(shared);
        } else {
          await host.start(shared, loopbackOnly: _loopbackOnly);
        }
      }
    } catch (error) {
      _error = '$error';
    }
    _busy = false;
    notifyListeners();
  }
}
