// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A saved, runtime-configurable agent definition.
///
/// References a [modelId] (a `ModelConfig.id`) rather than embedding model or
/// source details, so editing the underlying model updates every agent that
/// uses it.
class SavedAgentConfig {
  /// Creates a [SavedAgentConfig].
  const SavedAgentConfig({
    required this.id,
    required this.name,
    required this.modelId,
    this.description = '',
    this.instructions = '',
    this.temperature,
    this.maxOutputTokens,
  });

  /// Stable, app-unique identifier for this agent.
  final String id;

  /// Human-readable agent name.
  final String name;

  /// The [ModelConfig.id] this agent runs on.
  final String modelId;

  /// Optional description shown in the UI.
  final String description;

  /// System instructions applied to every run.
  final String instructions;

  /// Optional sampling temperature.
  final double? temperature;

  /// Optional maximum number of output tokens per response.
  final int? maxOutputTokens;

  /// Returns a copy with the given fields replaced.
  SavedAgentConfig copyWith({
    String? id,
    String? name,
    String? modelId,
    String? description,
    String? instructions,
    double? temperature,
    int? maxOutputTokens,
  }) => SavedAgentConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    modelId: modelId ?? this.modelId,
    description: description ?? this.description,
    instructions: instructions ?? this.instructions,
    temperature: temperature ?? this.temperature,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
  );

  /// Serializes this agent to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'modelId': modelId,
    'description': description,
    'instructions': instructions,
    if (temperature != null) 'temperature': temperature,
    if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
  };

  /// Reconstructs a [SavedAgentConfig] from [json].
  factory SavedAgentConfig.fromJson(Map<String, Object?> json) =>
      SavedAgentConfig(
        id: json['id']! as String,
        name: json['name']! as String,
        modelId: json['modelId']! as String,
        description: (json['description'] as String?) ?? '',
        instructions: (json['instructions'] as String?) ?? '',
        temperature: (json['temperature'] as num?)?.toDouble(),
        maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt(),
      );
}
