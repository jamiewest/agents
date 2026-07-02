// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'detection/model_format_heuristics.dart';
import 'model_profile_settings.dart';

/// How tools are conveyed to an OpenAI-compatible model.
enum ToolCallingMode {
  /// The standard Chat Completions `tools` field.
  native,

  /// Tool definitions injected into the system instructions; calls parsed
  /// from generated text via the model family's `ToolFormat`.
  promptInjected,

  /// Tools are never sent, even when the request carries them.
  none,
}

/// How reasoning appears in a model's text output.
enum ReasoningTagStyle {
  /// No in-text reasoning markup.
  none,

  /// Reasoning wrapped in `<think>…</think>` tags (Qwen3, QwQ,
  /// DeepSeek-R1).
  thinkTags,
}

/// Per-model behavior for an OpenAI-compatible endpoint.
///
/// Multi-model providers such as Groq serve many families through one
/// endpoint; the profile carries what varies between them. Resolve one
/// from stored settings and the model id with [OpenAIModelProfile.resolve].
final class OpenAIModelProfile {
  /// Creates a profile with explicit values.
  const OpenAIModelProfile({
    this.toolMode = ToolCallingMode.native,
    this.parallelToolCalls = true,
    this.reasoningTags = ReasoningTagStyle.none,
    this.fallbackFormatName,
  });

  /// Resolves a profile for [modelId] from stored [settings].
  ///
  /// Explicit settings win; absent or empty values fall back to
  /// name-based detection, then to defaults (native tools, parallel calls
  /// allowed, no reasoning tags). Unknown models default to native tools
  /// so a new model is never silently degraded.
  factory OpenAIModelProfile.resolve({
    required String modelId,
    Map<String, String> settings = const <String, String>{},
  }) {
    final detection = detectModelProfile(modelId);

    final toolMode = switch (_setting(settings, toolsModeSetting)) {
      toolsModePrompt => ToolCallingMode.promptInjected,
      toolsModeNone => ToolCallingMode.none,
      _ => ToolCallingMode.native,
    };

    final parallel = _setting(settings, toolsParallelSetting) != 'false';

    final reasoningTags = switch (_setting(settings, reasoningTagsSetting)) {
      reasoningTagsThink => ReasoningTagStyle.thinkTags,
      reasoningTagsNone => ReasoningTagStyle.none,
      _ =>
        detection.thinkTags
            ? ReasoningTagStyle.thinkTags
            : ReasoningTagStyle.none,
    };

    final formatName =
        _setting(settings, chatFormatSetting) ?? detection.formatName;

    return OpenAIModelProfile(
      toolMode: toolMode,
      parallelToolCalls: parallel,
      reasoningTags: reasoningTags,
      fallbackFormatName: formatName,
    );
  }

  /// How tools are conveyed to the model.
  final ToolCallingMode toolMode;

  /// Whether the model may return multiple tool calls per response.
  final bool parallelToolCalls;

  /// How in-text reasoning is recognized and stripped.
  final ReasoningTagStyle reasoningTags;

  /// The chat-format name used for the prompt-injected fallback, or
  /// `null` to use the default (Hermes) convention.
  final String? fallbackFormatName;

  static String? _setting(Map<String, String> settings, String key) {
    final value = settings[key]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}
