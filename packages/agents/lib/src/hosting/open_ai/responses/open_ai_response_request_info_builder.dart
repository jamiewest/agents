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

  /// Splits [tools] into the client-supplied function declarations this
  /// hosting layer can forward and the entries it cannot.
  static (List<AITool>? clientTools, List<Object?>? remainingTools)
  convertClientFunctionTools(List<Object?> tools) {
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
}

/// Converts a raw Responses tool entry into a declaration-only function, or
/// returns `null` when the entry is not a well-formed function declaration.
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

  final requestParameters = tool['parameters'];
  final parameters = requestParameters is Map
      ? requestParameters.cast<String, dynamic>()
      : <String, dynamic>{};

  final requestDescription = tool['description'];
  final description = requestDescription is String ? requestDescription : null;

  final requestStrict = tool['strict'];
  final strict = requestStrict is bool ? requestStrict : null;

  return ClientAIFunctionDeclaration(
    name: name,
    description: description,
    parametersSchema: parameters,
    strict: strict,
  );
}

/// A declaration-only function forwarded from a client request.
///
/// The declaration carries no executable body: it only tells the model that
/// the function exists, and any call the model makes is returned to the
/// client to execute.
class ClientAIFunctionDeclaration extends AIFunctionDeclaration {
  /// Creates a client-supplied function declaration.
  ClientAIFunctionDeclaration({
    required super.name,
    super.description,
    super.parametersSchema,
    bool? strict,
  }) : strict = strict {
    if (strict != null) {
      additionalProperties = <String, Object?>{'strict': strict};
    }
  }

  /// The request's `strict` flag, when it supplied one.
  final bool? strict;
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
