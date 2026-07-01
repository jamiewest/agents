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
    this.access,
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

  /// Optional per-agent access settings for built-in tools and context.
  ///
  /// When `null`, the configured harness defaults are used. Saved agents from
  /// older app versions omit this field and therefore keep their previous
  /// behavior until edited.
  final AgentAccessConfig? access;

  /// Returns a copy with the given fields replaced.
  SavedAgentConfig copyWith({
    String? id,
    String? name,
    String? modelId,
    String? description,
    String? instructions,
    double? temperature,
    int? maxOutputTokens,
    AgentAccessConfig? access,
  }) => SavedAgentConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    modelId: modelId ?? this.modelId,
    description: description ?? this.description,
    instructions: instructions ?? this.instructions,
    temperature: temperature ?? this.temperature,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    access: access ?? this.access,
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
    if (access != null) 'access': access!.toJson(),
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
        access: switch (json['access']) {
          final Map<dynamic, dynamic> access => AgentAccessConfig.fromJson(
            Map<String, Object?>.from(access),
          ),
          _ => null,
        },
      );
}

/// Per-agent access settings for built-in harness tools and context.
///
/// Defaults match the current Flutter harness behavior: safe passive
/// capabilities are enabled, while more sensitive device capabilities such as
/// location, detailed network information, and wake lock are opt-in.
class AgentAccessConfig {
  /// Creates an [AgentAccessConfig].
  const AgentAccessConfig({
    this.enableFileMemory = true,
    this.enableFileAccess = true,
    this.enableWebSearch = true,
    this.enableTodoList = true,
    this.enableAgentMode = true,
    this.enableSkills = true,
    this.enableTemporal = true,
    this.enableConnectivity = true,
    this.enableAppInfo = true,
    this.enableDeviceInfo = true,
    this.enableLocation = false,
    this.enableNetworkInfo = false,
    this.enableWakeLock = false,
  });

  /// Whether the agent may use file-backed memory context.
  final bool enableFileMemory;

  /// Whether the agent may use working-folder file context.
  final bool enableFileAccess;

  /// Whether the hosted web-search tool is available.
  final bool enableWebSearch;

  /// Whether todo-list context is available.
  final bool enableTodoList;

  /// Whether agent-mode context is available.
  final bool enableAgentMode;

  /// Whether skill context is available.
  final bool enableSkills;

  /// Whether current time context and the current-time tool are available.
  final bool enableTemporal;

  /// Whether connectivity context and the connectivity tool are available.
  final bool enableConnectivity;

  /// Whether app metadata tools are available.
  final bool enableAppInfo;

  /// Whether device information context and tools are available.
  final bool enableDeviceInfo;

  /// Whether location/geocoding context and tools are available.
  final bool enableLocation;

  /// Whether detailed local-network context and tools are available.
  final bool enableNetworkInfo;

  /// Whether the wake-lock tool is available.
  final bool enableWakeLock;

  /// Returns a copy with the given fields replaced.
  AgentAccessConfig copyWith({
    bool? enableFileMemory,
    bool? enableFileAccess,
    bool? enableWebSearch,
    bool? enableTodoList,
    bool? enableAgentMode,
    bool? enableSkills,
    bool? enableTemporal,
    bool? enableConnectivity,
    bool? enableAppInfo,
    bool? enableDeviceInfo,
    bool? enableLocation,
    bool? enableNetworkInfo,
    bool? enableWakeLock,
  }) => AgentAccessConfig(
    enableFileMemory: enableFileMemory ?? this.enableFileMemory,
    enableFileAccess: enableFileAccess ?? this.enableFileAccess,
    enableWebSearch: enableWebSearch ?? this.enableWebSearch,
    enableTodoList: enableTodoList ?? this.enableTodoList,
    enableAgentMode: enableAgentMode ?? this.enableAgentMode,
    enableSkills: enableSkills ?? this.enableSkills,
    enableTemporal: enableTemporal ?? this.enableTemporal,
    enableConnectivity: enableConnectivity ?? this.enableConnectivity,
    enableAppInfo: enableAppInfo ?? this.enableAppInfo,
    enableDeviceInfo: enableDeviceInfo ?? this.enableDeviceInfo,
    enableLocation: enableLocation ?? this.enableLocation,
    enableNetworkInfo: enableNetworkInfo ?? this.enableNetworkInfo,
    enableWakeLock: enableWakeLock ?? this.enableWakeLock,
  );

  /// Serializes this access config to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'enableFileMemory': enableFileMemory,
    'enableFileAccess': enableFileAccess,
    'enableWebSearch': enableWebSearch,
    'enableTodoList': enableTodoList,
    'enableAgentMode': enableAgentMode,
    'enableSkills': enableSkills,
    'enableTemporal': enableTemporal,
    'enableConnectivity': enableConnectivity,
    'enableAppInfo': enableAppInfo,
    'enableDeviceInfo': enableDeviceInfo,
    'enableLocation': enableLocation,
    'enableNetworkInfo': enableNetworkInfo,
    'enableWakeLock': enableWakeLock,
  };

  /// Reconstructs an [AgentAccessConfig] from [json].
  factory AgentAccessConfig.fromJson(Map<String, Object?> json) =>
      AgentAccessConfig(
        enableFileMemory: (json['enableFileMemory'] as bool?) ?? true,
        enableFileAccess: (json['enableFileAccess'] as bool?) ?? true,
        enableWebSearch: (json['enableWebSearch'] as bool?) ?? true,
        enableTodoList: (json['enableTodoList'] as bool?) ?? true,
        enableAgentMode: (json['enableAgentMode'] as bool?) ?? true,
        enableSkills: (json['enableSkills'] as bool?) ?? true,
        enableTemporal: (json['enableTemporal'] as bool?) ?? true,
        enableConnectivity: (json['enableConnectivity'] as bool?) ?? true,
        enableAppInfo: (json['enableAppInfo'] as bool?) ?? true,
        enableDeviceInfo: (json['enableDeviceInfo'] as bool?) ?? true,
        enableLocation: (json['enableLocation'] as bool?) ?? false,
        enableNetworkInfo: (json['enableNetworkInfo'] as bool?) ?? false,
        enableWakeLock: (json['enableWakeLock'] as bool?) ?? false,
      );
}
