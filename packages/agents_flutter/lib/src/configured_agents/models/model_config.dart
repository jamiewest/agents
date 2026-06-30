// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A model offered by a source, identified by the provider's model id.
class ModelConfig {
  /// Creates a [ModelConfig].
  const ModelConfig({
    required this.id,
    required this.sourceId,
    required this.modelId,
    this.displayName,
    this.settings = const {},
  });

  /// Stable, app-unique identifier for this model entry.
  final String id;

  /// The [ModelSourceConfig.id] this model belongs to.
  final String sourceId;

  /// The provider's model identifier (e.g. `gpt-4o`, `claude-haiku-4-5`).
  final String modelId;

  /// Optional friendly name; falls back to [modelId] in the UI when absent.
  final String? displayName;

  /// Non-secret model-specific settings.
  final Map<String, String> settings;

  /// The label to show for this model.
  String get label => displayName?.isNotEmpty == true ? displayName! : modelId;

  /// Returns a copy with the given fields replaced.
  ModelConfig copyWith({
    String? id,
    String? sourceId,
    String? modelId,
    String? displayName,
    Map<String, String>? settings,
  }) => ModelConfig(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    modelId: modelId ?? this.modelId,
    displayName: displayName ?? this.displayName,
    settings: settings ?? this.settings,
  );

  /// Serializes this model to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'sourceId': sourceId,
    'modelId': modelId,
    if (displayName != null) 'displayName': displayName,
    'settings': settings,
  };

  /// Reconstructs a [ModelConfig] from [json].
  factory ModelConfig.fromJson(Map<String, Object?> json) => ModelConfig(
    id: json['id']! as String,
    sourceId: json['sourceId']! as String,
    modelId: json['modelId']! as String,
    displayName: json['displayName'] as String?,
    settings: <String, String>{
      for (final entry
          in (json['settings'] as Map<Object?, Object?>? ?? const {}).entries)
        entry.key! as String: entry.value! as String,
    },
  );
}
