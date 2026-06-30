// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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
    required SecretStore secrets,
  }) : _secrets = secrets;

  /// The source/model store.
  final ModelSourceStore sources;

  /// The saved-agent store.
  final AgentConfigurationStore agents;

  final SecretStore _secrets;

  // --- Sources & secrets ---------------------------------------------------

  /// Saves [source], and when [apiKey] is non-null, stores it as the source's
  /// secret. Passing an empty [apiKey] clears the stored secret.
  Future<void> saveSource(ModelSourceConfig source, {String? apiKey}) async {
    await sources.saveSource(source);
    if (apiKey != null) {
      await setSourceApiKey(source.id, apiKey);
    }
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
    await _secrets.delete(ConfiguredAgentsKeys.sourceApiKeyKey(id));
  }

  // --- Models --------------------------------------------------------------

  /// Saves [model].
  Future<void> saveModel(ModelConfig model) => sources.saveModel(model);

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
    await sources.removeModel(id);
  }

  // --- Agents --------------------------------------------------------------

  /// Saves [agent].
  Future<void> saveAgent(SavedAgentConfig agent) => agents.saveAgent(agent);

  /// Deletes the agent [id].
  Future<void> deleteAgent(String id) => agents.removeAgent(id);

  Future<List<SavedAgentConfig>> _agentsForModel(String modelId) async {
    final all = await agents.listAgents();
    return all.where((agent) => agent.modelId == modelId).toList();
  }
}
