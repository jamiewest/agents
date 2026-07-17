// Copyright (c) Microsoft. All rights reserved.
//
// Ported from OpenAIChatCompletionsMapOptions.cs.

import '../../abstractions/agent_run_options.dart';
import 'open_ai_chat_completion_request_info.dart';

/// Options that control how an OpenAI ChatCompletions endpoint maps incoming
/// requests onto the target agent.
class OpenAIChatCompletionsMapOptions {
  /// The callback used to produce the [AgentRunOptions] for a request from
  /// the request-supplied generation and tool settings.
  ///
  /// By default this is set to [rejectRequestSettings], which throws when the
  /// request carries any setting that would otherwise be mapped onto the
  /// agent (for example `temperature`, `tools` or `tool_choice`). This
  /// prevents a caller from silently overriding the configuration of a
  /// self-contained agent.
  ///
  /// Hosting developers that want to honor specific request settings can
  /// supply their own callback that maps the desired fields onto an
  /// [AgentRunOptions] (or a subclass such as `ChatClientAgentRunOptions`),
  /// and may choose to throw, map, or ignore any field. Returning `null`
  /// runs the agent with its own configuration only.
  AgentRunOptions? Function(OpenAIChatCompletionRequestInfo request)
  runOptionsFactory = rejectRequestSettings;

  /// The default [runOptionsFactory] implementation. Throws an
  /// [UnsupportedError] when the request specifies any setting that would
  /// otherwise be mapped onto the agent, and otherwise returns `null` so
  /// that the agent runs with its own configuration only.
  ///
  /// [OpenAIChatCompletionRequestInfo.model] is intentionally not treated as
  /// an unsupported setting: it is informational, is not applied to local
  /// execution, and is a required field of the OpenAI ChatCompletions wire
  /// format (present on every request).
  static AgentRunOptions? rejectRequestSettings(
    OpenAIChatCompletionRequestInfo request,
  ) {
    final unsupported = <String>[
      if (request.temperature != null) 'temperature',
      if (request.topP != null) 'top_p',
      if (request.maxOutputTokens != null) 'max_completion_tokens',
      if (request.frequencyPenalty != null) 'frequency_penalty',
      if (request.presencePenalty != null) 'presence_penalty',
      if (request.seed != null) 'seed',
      if (request.stopSequences?.isNotEmpty ?? false) 'stop',
      if (request.responseFormat != null) 'response_format',
      if (request.tools?.isNotEmpty ?? false) 'tools',
      if (request.toolChoice != null) 'tool_choice',
    ];

    if (unsupported.isNotEmpty) {
      throw UnsupportedError(
        'The following request setting(s) are not supported by this agent '
        "endpoint: ${unsupported.join(', ')}. Configure an "
        'OpenAIChatCompletionsMapOptions.runOptionsFactory to map these '
        'settings onto the agent if they should be honored.',
      );
    }

    return null;
  }
}
