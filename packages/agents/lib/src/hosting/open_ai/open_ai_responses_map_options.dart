// Copyright (c) Microsoft. All rights reserved.
//
// Ported from OpenAIResponsesMapOptions.cs.

import '../../abstractions/agent_run_options.dart';
import 'open_ai_response_request_info.dart';

/// Options that control how an OpenAI Responses endpoint maps incoming
/// requests onto the target agent.
class OpenAIResponsesMapOptions {
  /// The callback used to produce the [AgentRunOptions] for a request from
  /// the request-supplied generation and tool settings.
  ///
  /// By default this is set to [rejectRequestSettings], which throws when the
  /// request carries any setting that would otherwise be mapped onto the
  /// agent (for example `temperature`, `instructions`, `tools` or
  /// `tool_choice`). This prevents a caller from silently overriding the
  /// configuration of a self-contained agent.
  ///
  /// Hosting developers that want to honor specific request settings can
  /// supply their own callback that maps the desired fields onto an
  /// [AgentRunOptions] (or a subclass such as `ChatClientAgentRunOptions`),
  /// and may choose to throw, map, or ignore any field. Returning `null`
  /// runs the agent with its own configuration only.
  AgentRunOptions? Function(OpenAIResponseRequestInfo request)
  runOptionsFactory = rejectRequestSettings;

  /// The default [runOptionsFactory] implementation. Throws an
  /// [UnsupportedError] when the request specifies any setting that would
  /// otherwise be mapped onto the agent, and otherwise returns `null` so
  /// that the agent runs with its own configuration only.
  ///
  /// [OpenAIResponseRequestInfo.model] is intentionally not treated as an
  /// unsupported setting: it is informational and is not applied to local
  /// execution.
  static AgentRunOptions? rejectRequestSettings(
    OpenAIResponseRequestInfo request,
  ) {
    final unsupported = <String>[
      if (request.temperature != null) 'temperature',
      if (request.topP != null) 'top_p',
      if (request.maxOutputTokens != null) 'max_output_tokens',
      if (request.instructions != null) 'instructions',
      if (request.tools?.isNotEmpty ?? false) 'tools',
      if (request.toolChoice != null) 'tool_choice',
    ];

    if (unsupported.isNotEmpty) {
      throw UnsupportedError(
        'The following request setting(s) are not supported by this agent '
        "endpoint: ${unsupported.join(', ')}. Configure an "
        'OpenAIResponsesMapOptions.runOptionsFactory to map these settings '
        'onto the agent if they should be honored.',
      );
    }

    return null;
  }
}
