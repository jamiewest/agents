// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'models/saved_agent_config.dart';
import 'storage/configured_agents_keys.dart';
import 'storage/key_value_store.dart';

/// Persists [SavedAgentConfig] entries in a [KeyValueStore].
class AgentConfigurationStore {
  /// Creates an [AgentConfigurationStore] backed by [store].
  AgentConfigurationStore(this._store);

  final KeyValueStore _store;

  /// Returns all saved agents, in unspecified order.
  Future<List<SavedAgentConfig>> listAgents() async {
    final keys = await _store.keys(prefix: ConfiguredAgentsKeys.agentPrefix);
    final agents = <SavedAgentConfig>[];
    for (final key in keys) {
      final raw = await _store.read(key);
      if (raw == null) continue;
      agents.add(
        SavedAgentConfig.fromJson(jsonDecode(raw) as Map<String, Object?>),
      );
    }
    return agents;
  }

  /// Returns the agent with [id], or `null` when absent.
  Future<SavedAgentConfig?> getAgent(String id) async {
    final raw = await _store.read('${ConfiguredAgentsKeys.agentPrefix}$id');
    if (raw == null) return null;
    return SavedAgentConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  /// Inserts or updates [agent].
  Future<void> saveAgent(SavedAgentConfig agent) => _store.write(
    '${ConfiguredAgentsKeys.agentPrefix}${agent.id}',
    jsonEncode(agent.toJson()),
  );

  /// Removes the agent with [id].
  Future<void> removeAgent(String id) =>
      _store.delete('${ConfiguredAgentsKeys.agentPrefix}$id');
}
