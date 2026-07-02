// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Per-model chat/tool behavior for OpenAI-compatible endpoints: settings
/// keys, capability profiles, prompt-injected tool formats, and format
/// auto-detection (name heuristics + GGUF metadata).
library;

export 'detection/gguf_inspection.dart';
export 'detection/gguf_metadata.dart';
export 'detection/model_format_heuristics.dart';
export 'model_profile_settings.dart';
export 'open_ai_compatible_chat_client.dart';
export 'open_ai_model_profile.dart';
export 'tool_formats/hermes_tool_format.dart';
export 'tool_formats/lfm2_tool_format.dart';
export 'tool_formats/llama3_tool_format.dart';
export 'tool_formats/mistral_tool_format.dart';
export 'tool_formats/think_tag_filter.dart';
export 'tool_formats/tool_call_stream_decoder.dart';
export 'tool_formats/tool_format.dart';
export 'tool_formats/tool_format_registry.dart';
