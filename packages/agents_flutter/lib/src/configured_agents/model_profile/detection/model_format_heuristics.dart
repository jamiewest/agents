// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Model-name heuristics that guess a chat format (and reasoning style)
/// from a provider model id or a GGUF file name.
///
/// Detection only pre-fills configuration; an explicit setting always
/// wins.
library;

/// What the heuristics inferred for one model name.
class ModelProfileDetection {
  /// Creates a [ModelProfileDetection].
  const ModelProfileDetection({this.formatName, this.thinkTags = false});

  /// The inferred chat-format name, or `null` when unrecognized.
  final String? formatName;

  /// Whether the model emits `<think>…</think>` reasoning in its text.
  final bool thinkTags;
}

/// One ordered detection rule: a lowercase substring and its outcome.
class _Rule {
  const _Rule(this.marker, this.format, {this.think = false});

  final String marker;
  final String format;
  final bool think;
}

/// Ordered first-match rules. Order matters: more specific markers
/// (`lfm2.5`, `qwen3`) come before their prefixes (`lfm2`, `qwen`).
const List<_Rule> _rules = <_Rule>[
  _Rule('lfm2.5', 'lfm2.5'),
  _Rule('lfm25', 'lfm2.5'),
  _Rule('lfm2', 'lfm2'),
  _Rule('qwq', 'qwen', think: true),
  _Rule('qwen3', 'qwen', think: true),
  _Rule('qwen', 'qwen'),
  _Rule('hermes', 'chatml'),
  _Rule('deepseek', 'chatml', think: true),
  _Rule('llama-3', 'llama3'),
  _Rule('llama3', 'llama3'),
  _Rule('llama 3', 'llama3'),
  _Rule('mixtral', 'mistral'),
  _Rule('mistral', 'mistral'),
  _Rule('ministral', 'mistral'),
  _Rule('magistral', 'mistral'),
  _Rule('gemma', 'gemma'),
  _Rule('smollm', 'chatml'),
  _Rule('tinyllama', 'chatml'),
  _Rule('phi-', 'chatml'),
  _Rule('phi3', 'chatml'),
  _Rule('phi4', 'chatml'),
];

/// Guesses the chat-format name for [modelIdOrFileName], or `null`.
///
/// Accepts provider model ids (`llama-3.3-70b-versatile`,
/// `qwen/qwen3-32b`) and GGUF file names
/// (`Qwen2.5-7B-Instruct-Q4_K_M.gguf`).
String? detectChatFormatName(String modelIdOrFileName) =>
    detectModelProfile(modelIdOrFileName).formatName;

/// Runs all heuristics for [modelIdOrFileName].
ModelProfileDetection detectModelProfile(String modelIdOrFileName) {
  final name = modelIdOrFileName.toLowerCase();
  for (final rule in _rules) {
    if (name.contains(rule.marker)) {
      return ModelProfileDetection(
        formatName: rule.format,
        thinkTags: rule.think,
      );
    }
  }
  return const ModelProfileDetection();
}
