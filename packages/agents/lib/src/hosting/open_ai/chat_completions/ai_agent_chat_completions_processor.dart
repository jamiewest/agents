// Copyright (c) Microsoft. All rights reserved.
//
// Ported from ChatCompletions/AIAgentChatCompletionsProcessor.cs.
//
// The C# original returns an ASP.NET `IResult`. This port exposes a
// framework-agnostic surface: a [Future] for non-streaming requests and a
// [Stream] of chunks for streaming requests. The shelf router serializes them.

import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/agent_run_options.dart';
import '../../../abstractions/ai_agent.dart';
import '../id_generator.dart';
import '../open_ai_chat_completions_map_options.dart';
import 'agent_response_extensions.dart';
import 'converters/chat_client_agent_run_options_converter.dart';
import 'models/chat_completion.dart';
import 'models/chat_completion_chunk.dart';
import 'models/completion_usage.dart';
import 'models/create_chat_completion.dart';

/// Drives an [AIAgent] from OpenAI chat-completion requests.
class AIAgentChatCompletionsProcessor {
  AIAgentChatCompletionsProcessor._();

  /// Produces the run options for [request] via [mapOptions].
  ///
  /// Throws an [UnsupportedError] when the request carries settings the
  /// configured factory does not accept (the default rejects all of them).
  static AgentRunOptions? _runOptions(
    CreateChatCompletion request,
    OpenAIChatCompletionsMapOptions? mapOptions,
  ) => (mapOptions ?? OpenAIChatCompletionsMapOptions()).runOptionsFactory(
    request.toRequestInfo(),
  );

  /// Runs [agent] for a non-streaming [request] and returns the completion.
  ///
  /// Throws an [UnsupportedError] when the request carries settings that
  /// [mapOptions] does not accept.
  static Future<ChatCompletion> createChatCompletion(
    AIAgent agent,
    CreateChatCompletion request, {
    OpenAIChatCompletionsMapOptions? mapOptions,
    CancellationToken? cancellationToken,
  }) async {
    final options = _runOptions(request, mapOptions);
    final chatMessages = request.messages
        .map((m) => m.toChatMessage())
        .toList();
    final response = await agent.run(
      null,
      options,
      messages: chatMessages,
      cancellationToken: cancellationToken,
    );
    return response.toChatCompletion(request);
  }

  /// Runs [agent] for a streaming [request], yielding completion chunks.
  ///
  /// Throws an [UnsupportedError] synchronously when the request carries
  /// settings that [mapOptions] does not accept, so callers can reject the
  /// request before starting the event stream.
  static Stream<ChatCompletionChunk> streamChatCompletion(
    AIAgent agent,
    CreateChatCompletion request, {
    OpenAIChatCompletionsMapOptions? mapOptions,
    CancellationToken? cancellationToken,
  }) {
    final options = _runOptions(request, mapOptions);
    return _streamChatCompletion(
      agent,
      request,
      options,
      cancellationToken: cancellationToken,
    );
  }

  static Stream<ChatCompletionChunk> _streamChatCompletion(
    AIAgent agent,
    CreateChatCompletion request,
    AgentRunOptions? options, {
    CancellationToken? cancellationToken,
  }) async* {
    final chatMessages = request.messages
        .map((m) => m.toChatMessage())
        .toList();
    final chunkId = IdGenerator.newId(
      'chatcmpl',
      delimiter: '-',
      stringLength: 13,
    );
    DateTime? createdAt;

    final updates = agent.runStreaming(
      null,
      options,
      messages: chatMessages,
      cancellationToken: cancellationToken,
    );

    await for (final update in updates) {
      final finishReason = update.finishReason?.value ?? 'stop';
      final role = update.role?.value ?? 'user';
      createdAt ??= update.createdAt;

      final choiceChunks = <ChatCompletionChoiceChunk>[];
      CompletionUsage? usage;

      for (final content in update.contents) {
        if (content is UsageContent) {
          usage = content.details.toCompletionUsage();
          continue;
        }

        final delta = _toDelta(content);
        if (delta == null) {
          continue;
        }
        delta.role = role;
        choiceChunks.add(
          ChatCompletionChoiceChunk(
            index: 0,
            delta: delta,
            finishReason: finishReason,
          ),
        );
      }

      yield ChatCompletionChunk(
        id: chunkId,
        created:
            (createdAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/
            1000,
        model: request.model,
        choices: choiceChunks,
        usage: usage,
      );
    }
  }
}

ChatCompletionDelta? _toDelta(AIContent content) {
  if (content is TextContent) {
    return ChatCompletionDelta(content: content.text);
  }
  if (content is DataContent && content.hasTopLevelMediaType('image')) {
    return ChatCompletionDelta(content: _dataAsString(content));
  }
  if (content is UriContent && content.hasTopLevelMediaType('image')) {
    return ChatCompletionDelta(content: content.uri.toString());
  }
  if (content is DataContent && content.hasTopLevelMediaType('audio')) {
    return ChatCompletionDelta(content: _dataAsString(content));
  }
  if (content is DataContent) {
    return ChatCompletionDelta(content: _dataAsString(content));
  }
  if (content is HostedFileContent) {
    return ChatCompletionDelta(content: content.fileId);
  }
  if (content is FunctionCallContent) {
    return ChatCompletionDelta(toolCalls: [content.toChoiceMessageToolCall()]);
  }
  return null;
}

String _dataAsString(DataContent content) {
  final data = content.data;
  if (data != null) {
    return base64Encode(data);
  }
  return content.uri ?? '';
}
