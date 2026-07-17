// Copyright (c) Microsoft. All rights reserved.
//
// Ported from Responses/AIAgentResponseExecutor.cs.
//
// Faithful for the text and function-call path: builds the agent input, runs
// the agent in streaming mode, and emits the OpenAI Responses streaming-event
// sequence (created → output_item.added → output_text.delta* → output_text.done
// → output_item.done → completed). Exotic content (audio/image/reasoning
// summary/workflow/MCP) follows the same generator pattern and can be added.

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/ai_agent.dart';
import '../open_ai_responses_map_options.dart';
import 'agent_invocation_context.dart';
import 'models/create_response.dart';
import 'models/item_resource.dart';
import 'models/response.dart';
import 'models/streaming_response_event.dart';
import 'open_ai_response_request_info_builder.dart';
import 'response_executor.dart';

/// A [ResponseExecutor] backed by a single [AIAgent].
class AIAgentResponseExecutor implements ResponseExecutor {
  /// Creates an [AIAgentResponseExecutor] for [agent].
  ///
  /// [mapOptions] controls how request-supplied settings are mapped onto the
  /// agent run; by default any such setting is rejected.
  AIAgentResponseExecutor(this._agent, {OpenAIResponsesMapOptions? mapOptions})
    : _mapOptions = mapOptions ?? OpenAIResponsesMapOptions();

  final AIAgent _agent;
  final OpenAIResponsesMapOptions _mapOptions;

  @override
  Future<ResponseError?> validateRequest(
    CreateResponse request, {
    CancellationToken? cancellationToken,
  }) async => validateRunOptions(request);

  /// Validates that the request-supplied settings are accepted by the
  /// configured run-options factory.
  ResponseError? validateRunOptions(CreateResponse request) {
    try {
      _mapOptions.runOptionsFactory(request.toRequestInfo());
      return null;
    } on UnsupportedError catch (e) {
      return ResponseError(
        code: 'unsupported_parameter',
        message: e.message ?? 'Unsupported request setting.',
      );
    }
  }

  @override
  Stream<StreamingResponseEvent> execute(
    AgentInvocationContext context,
    CreateResponse request, {
    List<ChatMessage>? conversationHistory,
    CancellationToken? cancellationToken,
  }) async* {
    final createdAt = clock.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    var sequence = 0;
    StreamingResponseEvent number(StreamingResponseEvent event) =>
        event..sequenceNumber = sequence++;

    // The hosting developer controls, via
    // OpenAIResponsesMapOptions.runOptionsFactory, which (if any) request
    // settings are mapped onto the agent run. By default no request setting
    // is mapped.
    final options = _mapOptions.runOptionsFactory(request.toRequestInfo());

    final messages = <ChatMessage>[
      ...?conversationHistory,
      ...request.input.getInputMessages().map((m) => m.toChatMessage()),
    ];

    Response inProgress() => Response(
      id: context.responseId,
      createdAt: createdAt,
      status: ResponseStatus.inProgress,
      model: request.model,
      instructions: request.instructions,
      conversationId: context.conversationId,
    );

    yield number(StreamingResponseCreated(inProgress()));
    yield number(StreamingResponseInProgress(inProgress()));

    final outputs = <ItemResource>[];
    var outputIndex = 0;
    String? messageItemId;
    final textBuffer = StringBuffer();
    ResponseUsage usage = ResponseUsage.zero;

    try {
      final updates = _agent.runStreaming(
        null,
        options,
        messages: messages,
        cancellationToken: cancellationToken,
      );

      await for (final update in updates) {
        for (final content in update.contents) {
          if (content is UsageContent) {
            usage = _toResponseUsage(content.details);
            continue;
          }
          if (content is TextContent) {
            if (messageItemId == null) {
              messageItemId = context.idGenerator.generateMessageId();
              yield number(
                StreamingOutputItemAdded(
                  outputIndex: outputIndex,
                  item: _assistantMessage(messageItemId, '', 'in_progress'),
                ),
              );
            }
            textBuffer.write(content.text);
            yield number(
              StreamingOutputTextDelta(
                itemId: messageItemId,
                outputIndex: outputIndex,
                contentIndex: 0,
                delta: content.text,
              ),
            );
          } else if (content is FunctionCallContent) {
            // Finalize any in-progress message item before the function call.
            if (messageItemId != null) {
              yield* _finishMessage(
                number,
                messageItemId,
                outputIndex,
                textBuffer.toString(),
                outputs,
              );
              messageItemId = null;
              textBuffer.clear();
              outputIndex++;
            }
            final fcId = context.idGenerator.generateFunctionCallId();
            final args = jsonEncode(content.arguments ?? <String, Object?>{});
            final item = _functionCall(
              fcId,
              content.callId,
              content.name,
              args,
            );
            yield number(
              StreamingOutputItemAdded(outputIndex: outputIndex, item: item),
            );
            yield number(
              StreamingFunctionCallArgumentsDone(
                itemId: fcId,
                outputIndex: outputIndex,
                arguments: args,
              ),
            );
            outputs.add(item);
            yield number(
              StreamingOutputItemDone(outputIndex: outputIndex, item: item),
            );
            outputIndex++;
          }
        }
      }

      if (messageItemId != null) {
        yield* _finishMessage(
          number,
          messageItemId,
          outputIndex,
          textBuffer.toString(),
          outputs,
        );
      }

      final completed = Response(
        id: context.responseId,
        createdAt: createdAt,
        status: ResponseStatus.completed,
        model: request.model,
        output: outputs,
        usage: usage,
        instructions: request.instructions,
        conversationId: context.conversationId,
      );
      yield number(StreamingResponseCompleted(completed));
    } catch (e) {
      final failed = Response(
        id: context.responseId,
        createdAt: createdAt,
        status: ResponseStatus.failed,
        model: request.model,
        output: outputs,
        error: ResponseError(message: e.toString()),
        conversationId: context.conversationId,
      );
      yield number(StreamingResponseFailed(failed));
    }
  }

  Stream<StreamingResponseEvent> _finishMessage(
    StreamingResponseEvent Function(StreamingResponseEvent) number,
    String itemId,
    int outputIndex,
    String text,
    List<ItemResource> outputs,
  ) async* {
    yield number(
      StreamingOutputTextDone(
        itemId: itemId,
        outputIndex: outputIndex,
        contentIndex: 0,
        text: text,
      ),
    );
    final item = _assistantMessage(itemId, text, 'completed');
    outputs.add(item);
    yield number(StreamingOutputItemDone(outputIndex: outputIndex, item: item));
  }

  static ItemResource _assistantMessage(
    String id,
    String text,
    String status,
  ) => ItemResource.fromJson({
    'id': id,
    'type': 'message',
    'role': 'assistant',
    'status': status,
    'content': [
      {'type': 'output_text', 'text': text, 'annotations': const []},
    ],
  });

  static ItemResource _functionCall(
    String id,
    String callId,
    String name,
    String arguments,
  ) => ItemResource.fromJson({
    'id': id,
    'type': 'function_call',
    'status': 'completed',
    'call_id': callId,
    'name': name,
    'arguments': arguments,
  });

  static ResponseUsage _toResponseUsage(UsageDetails usage) => ResponseUsage(
    inputTokens: usage.inputTokenCount ?? 0,
    outputTokens: usage.outputTokenCount ?? 0,
    totalTokens: usage.totalTokenCount ?? 0,
    cachedTokens: usage.cachedInputTokenCount ?? 0,
    reasoningTokens: usage.reasoningTokenCount ?? 0,
  );
}
