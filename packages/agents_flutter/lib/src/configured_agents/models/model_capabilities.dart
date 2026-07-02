// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'model_config.dart';

/// Capability metadata for a configured model, persisted in
/// [ModelConfig.settings].
///
/// The UI uses these flags to gate features per model — for example the
/// thinking toggle only appears when [supportsThinking] is true. Absent
/// settings fall back to conservative defaults: tool calling on, thinking
/// and vision off.
class ModelCapabilities {
  /// Creates a [ModelCapabilities].
  const ModelCapabilities({
    this.supportsThinking = false,
    this.supportsVision = false,
    this.supportsTools = true,
    this.contextLength,
    this.minMemoryMb,
  });

  /// Parses capabilities from a model's settings map.
  factory ModelCapabilities.fromSettings(Map<String, String> settings) =>
      ModelCapabilities(
        supportsThinking: settings[thinkingKey]?.trim() == 'true',
        supportsVision: settings[visionKey]?.trim() == 'true',
        supportsTools: settings[toolsKey]?.trim() != 'false',
        contextLength: int.tryParse(settings[contextLengthKey] ?? ''),
        minMemoryMb: int.tryParse(settings[minMemoryMbKey] ?? ''),
      );

  /// Settings key for [supportsThinking].
  static const String thinkingKey = 'capability.thinking';

  /// Settings key for [supportsVision].
  static const String visionKey = 'capability.vision';

  /// Settings key for [supportsTools].
  static const String toolsKey = 'capability.tools';

  /// Settings key for [contextLength].
  static const String contextLengthKey = 'capability.contextLength';

  /// Settings key for [minMemoryMb].
  static const String minMemoryMbKey = 'hardware.minMemoryMb';

  /// Whether the model supports extended reasoning ("thinking").
  final bool supportsThinking;

  /// Whether the model accepts image input.
  final bool supportsVision;

  /// Whether the model supports tool calling.
  final bool supportsTools;

  /// The model's context window in tokens, when known.
  final int? contextLength;

  /// Minimum device memory in megabytes, for local models.
  final int? minMemoryMb;

  /// Serializes to settings entries, omitting default values so existing
  /// models without capability metadata stay unchanged on disk.
  Map<String, String> toSettings() => {
    if (supportsThinking) thinkingKey: 'true',
    if (supportsVision) visionKey: 'true',
    if (!supportsTools) toolsKey: 'false',
    if (contextLength != null) contextLengthKey: '$contextLength',
    if (minMemoryMb != null) minMemoryMbKey: '$minMemoryMb',
  };
}

/// Capability accessors for [ModelConfig].
extension ModelConfigCapabilities on ModelConfig {
  /// The capabilities recorded in this model's settings.
  ModelCapabilities get capabilities =>
      ModelCapabilities.fromSettings(settings);
}
