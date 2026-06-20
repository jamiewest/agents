// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/AgentResponseExtensions.cs.
//
// Deviation: the upstream `ToChoiceMessageAnnotations` path (web-search
// citations via `CitationAnnotation`/`TextSpanAnnotatedRegion`) has no
// `extensions/ai` equivalent in this port, so annotations are not emitted.

import 'dart:convert';

import 'package:extensions/ai.dart';

import '../../../abstractions/agent_response.dart';
import '../id_generator.dart';
import 'models/chat_completion.dart';
import 'models/chat_completion_choice.dart';
import 'models/completion_usage.dart';
import 'models/create_chat_completion.dart';

/// Converts an [AgentResponse] to a [ChatCompletion].
extension AgentResponseChatCompletionExtensions on AgentResponse {
  /// Builds a [ChatCompletion] for [request] from this response.
  ChatCompletion toChatCompletion(CreateChatCompletion request) {
    return ChatCompletion(
      id: IdGenerator.newId('chatcmpl', delimiter: '-', stringLength: 13),
      choices: toChoices(),
      created: _unixSeconds(createdAt),
      model: request.model,
      usage: usage.toCompletionUsage(),
      serviceTier: request.serviceTier ?? 'default',
    );
  }

  /// Flattens this response's messages and contents into choices.
  List<ChatCompletionChoice> toChoices() {
    final choices = <ChatCompletionChoice>[];
    var index = 0;
    final reason = finishReason?.value ?? ChatFinishReason.stop.value;

    for (final message in messages) {
      for (final content in message.contents) {
        final choiceMessage = _toChoiceMessage(content);
        if (choiceMessage == null) {
          continue;
        }
        choiceMessage.role = message.role.value;
        choices.add(
          ChatCompletionChoice(
            index: index++,
            message: choiceMessage,
            finishReason: reason,
          ),
        );
      }
    }
    return choices;
  }
}

ChoiceMessage? _toChoiceMessage(AIContent content) {
  if (content is TextContent) {
    return ChoiceMessage(content: content.text);
  }
  if (content is DataContent && content.hasTopLevelMediaType('image')) {
    return ChoiceMessage(content: _dataAsString(content));
  }
  if (content is UriContent && content.hasTopLevelMediaType('image')) {
    return ChoiceMessage(content: content.uri.toString());
  }
  if (content is DataContent && content.hasTopLevelMediaType('audio')) {
    return ChoiceMessage(
      audio: ChoiceMessageAudio(data: _dataAsString(content), id: content.name),
    );
  }
  if (content is DataContent) {
    return ChoiceMessage(content: _dataAsString(content));
  }
  if (content is HostedFileContent) {
    return ChoiceMessage(content: content.fileId);
  }
  if (content is FunctionCallContent) {
    return ChoiceMessage(toolCalls: [content.toChoiceMessageToolCall()]);
  }
  // FunctionResultContent and any other content has no choice representation.
  return null;
}

/// Renders [content] as the base64 of its bytes, falling back to its URI.
String _dataAsString(DataContent content) {
  final data = content.data;
  if (data != null) {
    return base64Encode(data);
  }
  return content.uri ?? '';
}

int _unixSeconds(DateTime? value) =>
    (value ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;

/// Converts [UsageDetails] to a [CompletionUsage].
extension UsageDetailsCompletionExtensions on UsageDetails? {
  /// Maps token counts to a [CompletionUsage], or zero when null.
  CompletionUsage toCompletionUsage() {
    final usage = this;
    if (usage == null) {
      return CompletionUsage.zero;
    }
    return CompletionUsage(
      promptTokens: usage.inputTokenCount ?? 0,
      promptTokensDetails: PromptTokensDetails(
        cachedTokens: usage.cachedInputTokenCount ?? 0,
      ),
      completionTokens: usage.outputTokenCount ?? 0,
      completionTokensDetails: CompletionTokensDetails(
        reasoningTokens: usage.reasoningTokenCount ?? 0,
      ),
      totalTokens: usage.totalTokenCount ?? 0,
    );
  }
}

/// Converts a [FunctionCallContent] to a [ChoiceMessageToolCall].
extension FunctionCallToolCallExtensions on FunctionCallContent {
  /// Builds a tool call with JSON-serialized arguments.
  ChoiceMessageToolCall toChoiceMessageToolCall() {
    return ChoiceMessageToolCall(
      id: callId,
      function: ChoiceMessageFunctionCall(
        name: name,
        arguments: jsonEncode(arguments ?? <String, Object?>{}),
      ),
    );
  }
}
