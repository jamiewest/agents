// Copyright (c) Microsoft. All rights reserved.
//
// Ported from OpenAIChatCompletionRequestInfo.cs.

import 'package:extensions/ai.dart';

/// Exposes the request-supplied generation and tool settings of an OpenAI
/// ChatCompletions `create chat completion` request that a hosting developer
/// may choose to map onto the `AgentRunOptions` used to run the target agent.
///
/// This type is passed to
/// `OpenAIChatCompletionsMapOptions.runOptionsFactory`. By default no request
/// setting is mapped onto the agent, because an agent is typically
/// self-contained and allowing callers to override its configuration (for
/// example which tools it may invoke) can cause it to behave in ways its
/// author did not intend.
///
/// Tool and response-format settings are surfaced using their `extensions`
/// AI equivalents so that a hosting developer can map them directly without
/// re-parsing the wire format.
class OpenAIChatCompletionRequestInfo {
  /// The sampling temperature supplied on the request, if any.
  double? temperature;

  /// The nucleus sampling value (`top_p`) supplied on the request, if any.
  double? topP;

  /// The maximum number of output tokens supplied on the request, if any.
  int? maxOutputTokens;

  /// The frequency penalty supplied on the request, if any.
  double? frequencyPenalty;

  /// The presence penalty supplied on the request, if any.
  double? presencePenalty;

  /// The sampling seed supplied on the request, if any.
  int? seed;

  /// The stop sequences supplied on the request, if any.
  List<String>? stopSequences;

  /// The response format supplied on the request, if any.
  ChatResponseFormat? responseFormat;

  /// The model identifier supplied on the request, if any.
  ///
  /// This value is informational. It is not applied to local agent execution
  /// and is a required field of the OpenAI ChatCompletions wire format
  /// (present on every request), so it is intentionally excluded from the
  /// default `OpenAIChatCompletionsMapOptions.rejectRequestSettings`
  /// rejection.
  String? model;

  /// The tool selection mode (`tool_choice`) supplied on the request, if any.
  ChatToolMode? toolChoice;

  /// The tools supplied on the request, if any.
  List<AITool>? tools;
}
