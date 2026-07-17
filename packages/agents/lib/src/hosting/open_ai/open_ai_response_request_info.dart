// Copyright (c) Microsoft. All rights reserved.
//
// Ported from OpenAIResponseRequestInfo.cs.

import 'package:extensions/ai.dart';

/// Exposes the request-supplied generation and tool settings of an OpenAI
/// Responses `create response` request that a hosting developer may choose to
/// map onto the `AgentRunOptions` used to run the target agent.
///
/// This type is passed to `OpenAIResponsesMapOptions.runOptionsFactory`. By
/// default no request setting is mapped onto the agent, because an agent is
/// typically self-contained and allowing callers to override its
/// configuration (for example its instructions or which tools it may invoke)
/// can cause it to behave in ways its author did not intend.
///
/// Only the subset of request fields that are meaningful to map onto a local
/// agent run are exposed. The raw wire model is intentionally not surfaced.
class OpenAIResponseRequestInfo {
  /// The sampling temperature supplied on the request, if any.
  double? temperature;

  /// The nucleus sampling value (`top_p`) supplied on the request, if any.
  double? topP;

  /// The maximum number of output tokens supplied on the request, if any.
  int? maxOutputTokens;

  /// The instructions supplied on the request, if any.
  String? instructions;

  /// The model identifier supplied on the request, if any.
  ///
  /// This value is informational. It is not applied to local agent execution
  /// (the agent runs with its own chat client), so it is intentionally
  /// excluded from the default
  /// `OpenAIResponsesMapOptions.rejectRequestSettings` rejection.
  String? model;

  /// The raw `tools` array supplied on the request, if any.
  ///
  /// The OpenAI Responses wire format represents tools as JSON tool
  /// declarations rather than executable functions, so they are surfaced here
  /// as the raw decoded JSON values.
  List<Object?>? tools;

  /// The tool selection mode (`tool_choice`) supplied on the request, if any.
  ///
  /// The OpenAI Responses `tool_choice` value is mapped onto its
  /// [ChatToolMode] equivalent (`none`, `auto`, `required`, or a specific
  /// function). Values that have no equivalent are surfaced as `null`.
  ChatToolMode? toolChoice;
}
