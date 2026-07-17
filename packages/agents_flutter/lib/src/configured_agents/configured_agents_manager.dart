// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'agent_configuration_store.dart';
import 'configured_agent_exception.dart';
import 'models/model_config.dart';
import 'models/model_source_config.dart';
import 'models/saved_agent_config.dart';
import 'model_source_store.dart';
import 'storage/configured_agents_keys.dart';
import 'storage/secret_store.dart';

/// Coordinates the source/model/agent stores and the secret store, owning the
/// cross-store concerns that no single store can enforce on its own:
///
/// * API-key secrets, kept out of the configuration JSON entirely.
/// * Referential integrity — deleting a source that still has models, or a
///   model still used by agents, is blocked by default. Pass `cascade: true`
///   to remove dependents (and the source's secret) as well.
class ConfiguredAgentsManager {
  /// Creates a manager over the given stores.
  ConfiguredAgentsManager({
    required this.sources,
    required this.agents,
    required this._secrets,
  });

  /// The source/model store.
  final ModelSourceStore sources;

  /// The saved-agent store.
  final AgentConfigurationStore agents;

  final SecretStore _secrets;

  final StreamController<String> _agentChanges =
      StreamController<String>.broadcast();

  final StreamController<void> _configurationChanges =
      StreamController<void>.broadcast();

  /// Emits the id of a saved agent whenever its configuration changes
  /// (saved, deleted, or rewritten to drop a delegation).
  ///
  /// Long-lived consumers that built an [AIAgent] from a [SavedAgentConfig]
  /// — for example an open chat — can listen and rebuild the agent so
  /// edits to model, instructions, or tool access take effect without
  /// leaving and re-entering the conversation. The stream is a broadcast
  /// stream; a `null`-safe no-op if never listened to.
  Stream<String> get agentChanges => _agentChanges.stream;

  /// Emits after any successful source, model, or agent save or deletion,
  /// including cascade deletes.
  ///
  /// Coarser than [agentChanges]: listeners that derive state from the whole
  /// configuration — for example capability or provider classifications that
  /// depend on model and source records — can listen here and reload
  /// everything. Nothing is emitted when a mutation throws before changing
  /// any store.
  Stream<void> get configurationChanges => _configurationChanges.stream;

  /// Releases the change streams. Call when the manager is torn down;
  /// app-wide singletons that live for the process lifetime need not.
  Future<void> dispose() async {
    await _agentChanges.close();
    await _configurationChanges.close();
  }

  // --- Sources & secrets ---------------------------------------------------

  /// Saves [source], and when [apiKey] is non-null, stores it as the source's
  /// secret. Passing an empty [apiKey] clears the stored secret.
  Future<void> saveSource(ModelSourceConfig source, {String? apiKey}) async {
    await sources.saveSource(source);
    // The key must land before the notification: listeners rebuild agents on
    // configurationChanges and immediately read the source's API key.
    if (apiKey != null) {
      await setSourceApiKey(source.id, apiKey);
    }
    _notifyConfigurationChanged();
  }

  /// Stores (or, when [apiKey] is empty, clears) the API key for [sourceId].
  Future<void> setSourceApiKey(String sourceId, String apiKey) {
    final key = ConfiguredAgentsKeys.sourceApiKeyKey(sourceId);
    return apiKey.isEmpty ? _secrets.delete(key) : _secrets.write(key, apiKey);
  }

  /// Returns the API key for [sourceId], or `null` when none is stored.
  Future<String?> getSourceApiKey(String sourceId) =>
      _secrets.read(ConfiguredAgentsKeys.sourceApiKeyKey(sourceId));

  /// Whether a non-empty API key is stored for [sourceId].
  Future<bool> hasSourceApiKey(String sourceId) async {
    final key = await getSourceApiKey(sourceId);
    return key != null && key.isNotEmpty;
  }

  /// Deletes the source [id].
  ///
  /// Throws [ConfiguredAgentException] when models still belong to the source
  /// unless [cascade] is true, in which case those models — and any agents that
  /// use them — are removed as well, along with the source's API-key secret.
  Future<void> deleteSource(String id, {bool cascade = false}) async {
    final models = await sources.listModelsForSource(id);
    if (models.isNotEmpty && !cascade) {
      throw ConfiguredAgentException(
        'Source is still used by ${models.length} model(s). '
        'Remove them first or delete with cascade.',
      );
    }
    for (final model in models) {
      await deleteModel(model.id, cascade: true);
    }
    await sources.removeSource(id);
    _notifyConfigurationChanged();
    // Best-effort: the source record is already gone, and an orphaned
    // secret is harmless. A platform keychain rejection here must not
    // make the whole delete report failure.
    try {
      await _secrets.delete(ConfiguredAgentsKeys.sourceApiKeyKey(id));
    } catch (_) {}
  }

  // --- Models --------------------------------------------------------------

  /// Saves [model].
  Future<void> saveModel(ModelConfig model) async {
    await sources.saveModel(model);
    _notifyConfigurationChanged();
  }

  /// Deletes the model [id].
  ///
  /// Throws [ConfiguredAgentException] when agents still reference the model
  /// unless [cascade] is true, in which case those agents are removed too.
  Future<void> deleteModel(String id, {bool cascade = false}) async {
    final dependents = await _agentsForModel(id);
    if (dependents.isNotEmpty && !cascade) {
      throw ConfiguredAgentException(
        'Model is still used by ${dependents.length} agent(s). '
        'Remove them first or delete with cascade.',
      );
    }
    for (final agent in dependents) {
      await agents.removeAgent(agent.id);
    }
    await _removeDelegationReferences({
      for (final agent in dependents) agent.id,
    });
    await sources.removeModel(id);
    _notifyConfigurationChanged();
  }

  // --- Agents --------------------------------------------------------------

  /// Saves [agent].
  ///
  /// Throws [ConfiguredAgentException] when a delegation is self-referential,
  /// duplicated, or references a saved agent that does not exist.
  Future<void> saveAgent(SavedAgentConfig agent) async {
    if (agent.delegations.isNotEmpty) {
      final known = {
        for (final existing in await agents.listAgents()) existing.id,
      };
      final seen = <String>{};
      for (final delegation in agent.delegations) {
        if (delegation.agentId == agent.id) {
          throw ConfiguredAgentException(
            'Agent "${agent.name}" cannot delegate to itself.',
          );
        }
        if (!seen.add(delegation.agentId)) {
          throw ConfiguredAgentException(
            'Agent "${agent.name}" lists the same delegate more than once.',
          );
        }
        if (!known.contains(delegation.agentId)) {
          throw ConfiguredAgentException(
            'Agent "${agent.name}" delegates to an agent that does not '
            'exist.',
          );
        }
      }
    }
    await agents.saveAgent(agent);
    _notifyAgentChanged(agent.id);
    _notifyConfigurationChanged();
  }

  /// Deletes the agent [id].
  ///
  /// Throws [ConfiguredAgentException] when other agents delegate to the
  /// agent unless [cascade] is true, in which case those delegation
  /// references are removed first.
  Future<void> deleteAgent(String id, {bool cascade = false}) async {
    final referrers = await _agentsDelegatingTo({id});
    if (referrers.isNotEmpty && !cascade) {
      throw ConfiguredAgentException(
        'Agent is a delegate of ${referrers.length} other agent(s). '
        'Remove those delegations first or delete with cascade.',
      );
    }
    await _removeDelegationReferences({id});
    await agents.removeAgent(id);
    _notifyAgentChanged(id);
    _notifyConfigurationChanged();
  }

  Future<List<SavedAgentConfig>> _agentsForModel(String modelId) async {
    final all = await agents.listAgents();
    return all.where((agent) => agent.modelId == modelId).toList();
  }

  Future<List<SavedAgentConfig>> _agentsDelegatingTo(
    Set<String> agentIds,
  ) async {
    final all = await agents.listAgents();
    return all
        .where(
          (agent) => agent.delegations.any(
            (delegation) => agentIds.contains(delegation.agentId),
          ),
        )
        .toList();
  }

  void _notifyAgentChanged(String agentId) {
    if (!_agentChanges.isClosed) {
      _agentChanges.add(agentId);
    }
  }

  void _notifyConfigurationChanged() {
    if (!_configurationChanges.isClosed) {
      _configurationChanges.add(null);
    }
  }

  /// Rewrites any remaining agents so they no longer delegate to the removed
  /// [agentIds].
  Future<void> _removeDelegationReferences(Set<String> agentIds) async {
    if (agentIds.isEmpty) {
      return;
    }
    final referrers = await _agentsDelegatingTo(agentIds);
    for (final referrer in referrers) {
      await agents.saveAgent(
        referrer.copyWith(
          delegations: referrer.delegations
              .where((delegation) => !agentIds.contains(delegation.agentId))
              .toList(),
        ),
      );
      _notifyAgentChanged(referrer.id);
    }
  }
}
