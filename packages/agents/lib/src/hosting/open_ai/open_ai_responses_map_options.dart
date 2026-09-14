// Copyright (c) Microsoft. All rights reserved.
//
// Ported from OpenAIResponsesMapOptions.cs.

import 'package:extensions/ai.dart';

import '../../abstractions/agent_run_options.dart';
import '../../ai/chat_client/chat_client_agent_run_options.dart';
import 'open_ai_response_request_info.dart';
import 'responses/open_ai_response_request_info_builder.dart';

/// Options that control how an OpenAI Responses endpoint maps incoming
/// requests onto the target agent.
class OpenAIResponsesMapOptions {
  AgentRunOptions? Function(OpenAIResponseRequestInfo request)?
  _runOptionsFactory;

  /// The callback used to produce the [AgentRunOptions] for a request from
  /// the request-supplied generation and tool settings.
  ///
  /// By default this uses [rejectRequestSettings], which throws when the
  /// request carries any setting that would otherwise be mapped onto the
  /// agent (for example `temperature`, `instructions`, `tools` or
  /// `tool_choice`). This prevents a caller from silently overriding the
  /// configuration of a self-contained agent. Enabling
  /// [dangerouslyAllowClientFunctionTools] selects a default mapping that
  /// forwards function declarations while continuing to reject other
  /// unsupported settings.
  ///
  /// Hosting developers that want to honor specific request settings can
  /// supply their own callback that maps the desired fields onto an
  /// [AgentRunOptions] (or a subclass such as [ChatClientAgentRunOptions]),
  /// and may choose to throw, map, or ignore any field. A custom callback
  /// receives all request settings, including the complete
  /// [OpenAIResponseRequestInfo.tools] collection, and replaces the default
  /// mapping. Its result is used unchanged, regardless of
  /// [dangerouslyAllowClientFunctionTools]. Returning `null` runs the agent
  /// with its own configuration only.
  AgentRunOptions? Function(OpenAIResponseRequestInfo request)
  get runOptionsFactory =>
      _runOptionsFactory ??
      (dangerouslyAllowClientFunctionTools
          ? mapClientFunctionTools
          : rejectRequestSettings);

  set runOptionsFactory(
    AgentRunOptions? Function(OpenAIResponseRequestInfo request) value,
  ) {
    _runOptionsFactory = value;
  }

  /// Whether the default mapping forwards client-provided function
  /// declarations in the agent's run options.
  ///
  /// This setting is dangerous because client-provided function names,
  /// descriptions, and schemas can change which tools the model chooses. The
  /// declarations do not contain executable code; the downstream chat client
  /// and provider determine how function calls are handled.
  ///
  /// A client function may cause the model to choose it instead of a function
  /// configured by the hosted agent developer, even when their names do not
  /// conflict. Function arguments and any data included in those arguments
  /// are then returned to the client.
  ///
  /// The default is `false`, which leaves client-provided tools subject to
  /// [runOptionsFactory] and its default [rejectRequestSettings] behavior.
  /// The request's `tool_choice` is not enabled by this setting and remains
  /// controlled by [runOptionsFactory].
  ///
  /// With the default mapping, accepted function declarations are converted
  /// to [ChatClientAgentRunOptions.chatOptions] tools. Other tool types and
  /// unsupported request settings are rejected. This setting has no effect
  /// when a custom [runOptionsFactory] is supplied; that callback owns the
  /// entire mapping.
  ///
  /// The hosting layer does not require a particular agent implementation.
  /// Agents that do not consume these options may ignore the mapped
  /// functions; enabling this setting does not add function support to them.
  ///
  /// Function names are not checked for conflicts or deduplicated. The
  /// downstream chat client and provider determine whether duplicate names
  /// are accepted and which function is selected. The agent's parallel tool
  /// calling configuration is not changed.
  bool dangerouslyAllowClientFunctionTools = false;

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
    _throwIfUnsupportedRequestSettings(request, request.tools);
    return null;
  }

  /// The [runOptionsFactory] used when [dangerouslyAllowClientFunctionTools]
  /// is enabled: forwards well-formed client function declarations and
  /// rejects every other tool entry and unsupported setting.
  static AgentRunOptions? mapClientFunctionTools(
    OpenAIResponseRequestInfo request,
  ) {
    final tools = request.tools;
    if (tools == null || tools.isEmpty) {
      return rejectRequestSettings(request);
    }

    final (clientTools, remainingTools) =
        OpenAIResponseRequestInfoBuilder.convertClientFunctionTools(tools);
    _throwIfUnsupportedRequestSettings(request, remainingTools);

    return (clientTools != null && clientTools.isNotEmpty)
        ? ChatClientAgentRunOptions(
            chatOptions: ChatOptions()..tools = clientTools,
          )
        : null;
  }

  static void _throwIfUnsupportedRequestSettings(
    OpenAIResponseRequestInfo request,
    List<Object?>? tools,
  ) {
    final unsupported = <String>[
      if (request.temperature != null) 'temperature',
      if (request.topP != null) 'top_p',
      if (request.maxOutputTokens != null) 'max_output_tokens',
      if (request.instructions != null) 'instructions',
      if (tools?.isNotEmpty ?? false) 'tools',
      if (request.hasToolChoice || request.toolChoice != null) 'tool_choice',
    ];

    if (unsupported.isNotEmpty) {
      throw UnsupportedError(
        'The following request setting(s) are not supported by this agent '
        "endpoint: ${unsupported.join(', ')}. Configure an "
        'OpenAIResponsesMapOptions.runOptionsFactory to map these settings '
        'onto the agent if they should be honored.',
      );
    }
  }
}
