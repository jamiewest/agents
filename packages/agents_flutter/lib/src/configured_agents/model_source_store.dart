// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'models/model_config.dart';
import 'models/model_source_config.dart';
import 'storage/configured_agents_keys.dart';
import 'storage/key_value_store.dart';

/// Persists [ModelSourceConfig] and [ModelConfig] entries in a
/// [KeyValueStore].
///
/// This store handles plain CRUD for sources and models. Cross-cutting concerns
/// — API-key secrets and referential-integrity (block/cascade) deletes — live
/// in `ConfiguredAgentsManager`, which is the only layer that sees sources,
/// models, agents, and secrets together.
class ModelSourceStore {
  /// Creates a [ModelSourceStore] backed by [store].
  ModelSourceStore(this._store);

  final KeyValueStore _store;

  /// Returns all saved sources, in unspecified order.
  Future<List<ModelSourceConfig>> listSources() async {
    final keys = await _store.keys(prefix: ConfiguredAgentsKeys.sourcePrefix);
    final sources = <ModelSourceConfig>[];
    for (final key in keys) {
      final raw = await _store.read(key);
      if (raw == null) continue;
      sources.add(
        ModelSourceConfig.fromJson(jsonDecode(raw) as Map<String, Object?>),
      );
    }
    return sources;
  }

  /// Returns the source with [id], or `null` when absent.
  Future<ModelSourceConfig?> getSource(String id) async {
    final raw = await _store.read('${ConfiguredAgentsKeys.sourcePrefix}$id');
    if (raw == null) return null;
    return ModelSourceConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  /// Inserts or updates [source].
  Future<void> saveSource(ModelSourceConfig source) => _store.write(
    '${ConfiguredAgentsKeys.sourcePrefix}${source.id}',
    jsonEncode(source.toJson()),
  );

  /// Removes the source with [id] only. Does not touch dependent models or the
  /// API-key secret; use `ConfiguredAgentsManager.deleteSource` for that.
  Future<void> removeSource(String id) =>
      _store.delete('${ConfiguredAgentsKeys.sourcePrefix}$id');

  /// Returns all saved models, in unspecified order.
  Future<List<ModelConfig>> listModels() async {
    final keys = await _store.keys(prefix: ConfiguredAgentsKeys.modelPrefix);
    final models = <ModelConfig>[];
    for (final key in keys) {
      final raw = await _store.read(key);
      if (raw == null) continue;
      models.add(ModelConfig.fromJson(jsonDecode(raw) as Map<String, Object?>));
    }
    return models;
  }

  /// Returns the models belonging to source [sourceId].
  Future<List<ModelConfig>> listModelsForSource(String sourceId) async {
    final models = await listModels();
    return models.where((model) => model.sourceId == sourceId).toList();
  }

  /// Returns the model with [id], or `null` when absent.
  Future<ModelConfig?> getModel(String id) async {
    final raw = await _store.read('${ConfiguredAgentsKeys.modelPrefix}$id');
    if (raw == null) return null;
    return ModelConfig.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  /// Inserts or updates [model].
  Future<void> saveModel(ModelConfig model) => _store.write(
    '${ConfiguredAgentsKeys.modelPrefix}${model.id}',
    jsonEncode(model.toJson()),
  );

  /// Removes the model with [id] only.
  Future<void> removeModel(String id) =>
      _store.delete('${ConfiguredAgentsKeys.modelPrefix}$id');
}
