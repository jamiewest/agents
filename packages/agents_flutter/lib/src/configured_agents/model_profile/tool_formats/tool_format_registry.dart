// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'hermes_tool_format.dart';
import 'lfm2_tool_format.dart';
import 'llama3_tool_format.dart';
import 'mistral_tool_format.dart';
import 'tool_format.dart';

/// Maps chat-format names to their prompt-injected [ToolFormat].
///
/// Uses the same names as the local llama chat-format registry
/// (`agents_llama`'s `resolveChatFormat`) so one stored `chat.format`
/// value drives both local rendering and the remote fallback. `gemma`
/// intentionally maps to the Hermes convention — see [HermesToolFormat].
const Map<String, ToolFormat> _toolFormats = <String, ToolFormat>{
  'qwen': HermesToolFormat(),
  'chatml': HermesToolFormat(),
  'gemma': HermesToolFormat(),
  'llama3': Llama3ToolFormat(),
  'mistral': MistralToolFormat(),
  'lfm2': Lfm2ToolFormat(),
  'lfm2-vl': Lfm2ToolFormat(),
  'lfm2.5': Lfm2ToolFormat(style: LfmToolTagStyle.lfm25),
  'lfm2.5-vl': Lfm2ToolFormat(style: LfmToolTagStyle.lfm25),
  'lfm25': Lfm2ToolFormat(style: LfmToolTagStyle.lfm25),
  'lfm25-vl': Lfm2ToolFormat(style: LfmToolTagStyle.lfm25),
};

/// The chat-format names with a prompt-injected tool fallback.
Set<String> get supportedToolFormatNames => _toolFormats.keys.toSet();

/// Resolves a chat-format [name] to its [ToolFormat].
///
/// Returns the Hermes format for `null`/empty (the most widely followed
/// convention), or `null` for an unknown name.
ToolFormat? resolveToolFormat(String? name) {
  if (name == null || name.isEmpty) return const HermesToolFormat();
  return _toolFormats[name.toLowerCase()];
}
