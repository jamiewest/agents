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
    ..toolChoice = _toChatToolMode(toolChoice)
    ..hasToolChoice = toolChoice != null;
}

/// Splits raw request tool declarations into client function tools and the
/// declarations that are not function tools.
(List<AITool>?, List<Object?>?) convertClientFunctionTools(
  List<Object?> tools,
) {
  List<AITool>? clientTools;
  List<Object?>? remainingTools;

  for (final tool in tools) {
    final functionTool = _toFunctionTool(tool);
    if (functionTool != null) {
      (clientTools ??= <AITool>[]).add(functionTool);
    } else {
      (remainingTools ??= <Object?>[]).add(tool);
    }
  }

  return (clientTools, remainingTools);
}

ClientAIFunctionDeclaration? _toFunctionTool(Object? tool) {
  if (tool is! Map) {
    return null;
  }
  if (tool['type'] != 'function') {
    return null;
  }
  final name = tool['name'];
  if (name is! String || name.isEmpty) {
    return null;
  }

  final parameters = tool['parameters'];
  final description = tool['description'];
  final strict = tool['strict'];

  return ClientAIFunctionDeclaration(
    name: name,
    description: description is String ? description : null,
    parametersSchema: parameters is Map
        ? parameters.cast<String, dynamic>()
        : const <String, dynamic>{},
    strict: strict is bool ? strict : null,
  );
}

/// A function declaration built from a client-supplied `tools` entry.
///
/// It declares the function to the model but carries no executable body: the
/// downstream chat client and provider decide how a call to it is handled.
class ClientAIFunctionDeclaration extends AIFunctionDeclaration {
  /// Creates a declaration for a client-supplied function tool.
  ClientAIFunctionDeclaration({
    required super.name,
    super.description,
    super.parametersSchema,
    bool? strict,
  }) {
    if (strict != null) {
      additionalProperties = AdditionalPropertiesDictionary()
        ..['strict'] = strict;
    }
  }
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
