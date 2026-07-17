// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/OpenAIResponseRequestInfoBuilder.cs.

import 'package:extensions/ai.dart';

import '../open_ai_response_request_info.dart';
import 'models/create_response.dart';

/// Builds an [OpenAIResponseRequestInfo] from a [CreateResponse] request.
extension OpenAIResponseRequestInfoBuilder on CreateResponse {
  /// Extracts the request-supplied generation and tool settings.
  OpenAIResponseRequestInfo toRequestInfo() => OpenAIResponseRequestInfo()
    ..temperature = temperature
    ..topP = topP
    ..maxOutputTokens = maxOutputTokens
    ..instructions = instructions
    ..model = model
    ..tools = (tools?.isNotEmpty ?? false) ? List<Object?>.of(tools!) : null
    ..toolChoice = _toChatToolMode(toolChoice);
}

/// Maps an OpenAI Responses `tool_choice` value onto its [ChatToolMode]
/// equivalent.
///
/// The Responses `tool_choice` is either a string (`none`, `auto` or
/// `required`) or an object identifying a specific tool (for example
/// `{ "type": "function", "name": "..." }`). Values that have no
/// [ChatToolMode] equivalent are mapped to `null`.
ChatToolMode? _toChatToolMode(Object? toolChoice) {
  if (toolChoice is String) {
    switch (toolChoice) {
      case 'none':
        return ChatToolMode.none;
      case 'auto':
        return ChatToolMode.auto;
      case 'required':
        return ChatToolMode.requireAny;
      default:
        return null;
    }
  }

  if (toolChoice is Map) {
    final type = toolChoice['type'];
    final name = toolChoice['name'];
    if (type == 'function' && name is String && name.isNotEmpty) {
      return ChatToolMode.requireSpecific(name);
    }
    return null;
  }

  return null;
}
