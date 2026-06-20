// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/Converters/ChatClientAgentRunOptionsConverter.cs.

import 'package:extensions/ai.dart';

import '../../../../ai/chat_client/chat_client_agent_run_options.dart';
import '../models/create_chat_completion.dart';
import '../models/response_format.dart';
import '../models/tool.dart';
import '../models/tool_choice.dart';

/// Builds [ChatClientAgentRunOptions] from a [CreateChatCompletion] request.
extension ChatClientAgentRunOptionsConverter on CreateChatCompletion {
  /// Maps this request's sampling, tool, and format settings to run options.
  ChatClientAgentRunOptions buildOptions() {
    final chatOptions = ChatOptions(
      temperature: temperature,
      maxOutputTokens: maxCompletionTokens,
      frequencyPenalty: frequencyPenalty,
      presencePenalty: presencePenalty,
      seed: seed,
      topP: topP,
      stopSequences: stop?.sequenceList ?? <String>[],
      responseFormat: responseFormat?._toChatResponseFormat(),
    );

    final choice = toolChoice;
    if (choice != null) {
      chatOptions.toolMode = choice._toChatToolMode();
    }

    final requestTools = tools;
    if (requestTools != null && requestTools.isNotEmpty) {
      chatOptions.tools = requestTools.map((t) => t._toAITool()).toList();
    }

    return ChatClientAgentRunOptions(chatOptions: chatOptions);
  }
}

extension on ResponseFormat {
  ChatResponseFormat _toChatResponseFormat() {
    if (isText) {
      return ChatResponseFormat.text;
    }
    if (isJsonObject) {
      return ChatResponseFormat.json;
    }
    if (isJsonSchema) {
      final schema = jsonSchema!.jsonSchema;
      return ChatResponseFormat.forJsonSchema(
        schema: schema.schema,
        schemaName: schema.name,
        schemaDescription: schema.description,
      );
    }
    throw ArgumentError('Unrecognized response format');
  }
}

extension on Tool {
  AITool _toAITool() {
    final tool = this;
    if (tool is FunctionTool) {
      final function = tool.function;
      return _DeclaredFunction(
        name: function.name,
        description: function.description,
        parametersSchema: function.parameters,
      );
    }
    if (tool is CustomTool) {
      final custom = tool.custom;
      return _CustomAITool(
        name: custom.name,
        description: custom.description,
        additionalProperties: custom.format?.additionalProperties,
      );
    }
    throw ArgumentError('Unrecognized tool');
  }
}

extension on ToolChoice {
  ChatToolMode? _toChatToolMode() {
    if (isMode) {
      switch (mode) {
        case 'auto':
          return ChatToolMode.auto;
        case 'none':
          return ChatToolMode.none;
        case 'required':
          return ChatToolMode.requireAny;
        default:
          return null;
      }
    }
    if (isAllowedTools) {
      switch (allowedTools!.allowedTools.mode) {
        case 'auto':
          return ChatToolMode.auto;
        case 'required':
          return ChatToolMode.requireAny;
        default:
          return null;
      }
    }
    if (isFunctionTool) {
      return ChatToolMode.requireSpecific(functionTool!.function.name);
    }
    if (isCustomTool) {
      return ChatToolMode.requireSpecific(customTool!.custom.name);
    }
    throw ArgumentError('Unrecognized tool choice');
  }
}

/// A declaration-only function tool (no invocation body).
class _DeclaredFunction extends AIFunctionDeclaration {
  _DeclaredFunction({
    required super.name,
    super.description,
    super.parametersSchema,
  });
}

/// A declaration-only custom tool carrying its format properties.
class _CustomAITool extends AITool {
  _CustomAITool({
    required super.name,
    super.description,
    Map<String, Object?>? additionalProperties,
  }) {
    this.additionalProperties = additionalProperties ?? <String, Object?>{};
  }
}
