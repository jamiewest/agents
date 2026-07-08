// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The [ModelConfig.settings] keys that describe a model's chat/tool
/// behavior, shared by the client factory and any editor UI so the two
/// cannot drift.
///
/// All values are stored as strings. An absent key or an empty value means
/// "auto": resolve the behavior from the model id via
/// `detectModelProfile`.
library;

/// Chat-format name (e.g. `qwen`, `llama3`), or empty for auto-detect.
///
/// Uses the same names as the local llama chat-format registry so one
/// selection drives both local rendering and the remote prompt-injected
/// tool fallback.
const String chatFormatSetting = 'chat.format';

/// Legacy key for [chatFormatSetting] written by earlier versions for
/// local llama models; read as a fallback.
const String legacyLlamaFormatSetting = 'llama.format';

/// How tools are conveyed to an OpenAI-compatible model:
/// `native`, `prompt`, or `none`. Empty means auto.
const String toolsModeSetting = 'tools.mode';

/// Whether the model may return multiple tool calls per response:
/// `true` or `false`. Empty means auto (allowed).
const String toolsParallelSetting = 'tools.parallel';

/// How reasoning is tagged in the model's text output:
/// `auto`, `think`, or `none`.
const String reasoningTagsSetting = 'chat.reasoningTags';

/// Value of [toolsModeSetting] for OpenAI-native function calling.
const String toolsModeNative = 'native';

/// Value of [toolsModeSetting] for prompt-injected tool calling.
const String toolsModePrompt = 'prompt';

/// Value of [toolsModeSetting] that disables tools entirely.
const String toolsModeNone = 'none';

/// Value of [reasoningTagsSetting] that strips `<think>` tags.
const String reasoningTagsThink = 'think';

/// Value of [reasoningTagsSetting] that disables tag handling.
const String reasoningTagsNone = 'none';

/// How a scheduled task delivers its prompt to this model.
///
/// [taskPromptRoleSystem] sends it as a system-role turn — only for models
/// whose chat template renders a standalone system message and generates
/// from it (e.g. Gemma). [taskPromptRoleUser] sends it as a hidden user
/// message. Absent or empty means [taskPromptRoleUser]: the safe default
/// that works on every provider, since hosted providers (Anthropic, Gemini,
/// OpenAI-compatible) hoist system text into a separate field and reject a
/// system-only turn.
const String taskPromptRoleSetting = 'tasks.promptRole';

/// Value of [taskPromptRoleSetting] selecting a system-role task prompt.
const String taskPromptRoleSystem = 'system';

/// Value of [taskPromptRoleSetting] selecting a hidden user-role task prompt.
const String taskPromptRoleUser = 'user';
