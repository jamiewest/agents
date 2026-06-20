// Copyright (c) Microsoft. All rights reserved.

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/hosting/open_ai/responses/ai_agent_response_executor.dart';
import 'package:agents/src/hosting/open_ai/responses/in_memory_responses_service.dart';
import 'package:agents/src/hosting/open_ai/responses/models/create_response.dart';
import 'package:agents/src/hosting/open_ai/responses/models/streaming_response_event.dart';
import 'package:agents/src/hosting/open_ai/responses/responses_handler.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  InMemoryResponsesService newService() =>
      InMemoryResponsesService(AIAgentResponseExecutor(_EchoAgent()));

  group('CreateResponse.fromJson', () {
    test('parses string input and message-list input', () {
      final fromString = CreateResponse.fromJson({
        'model': 'gpt-4o',
        'input': 'hello',
      });
      expect(fromString.input.isText, isTrue);
      expect(
        fromString.input.getInputMessages().single.toChatMessage().text,
        'hello',
      );

      final fromMessages = CreateResponse.fromJson({
        'input': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(fromMessages.input.isMessages, isTrue);
    });
  });

  group('InMemoryResponsesService (non-streaming)', () {
    test('creates, stores, and retrieves a response', () async {
      final service = newService();
      final response = await service.createResponse(
        CreateResponse.fromJson({'model': 'gpt-4o', 'input': 'hi'}),
      );

      final json = response.toJson();
      expect(json['object'], 'response');
      expect(json['status'], 'completed');
      final output = json['output'] as List;
      expect(output, hasLength(1));
      final message = output.single as Map;
      expect(message['type'], 'message');
      expect(message['role'], 'assistant');
      final content = (message['content'] as List).single as Map;
      expect(content['type'], 'output_text');
      expect(content['text'], 'echo: hi');

      final fetched = await service.getResponse(response.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, response.id);
    });

    test('lists input items and deletes the response', () async {
      final service = newService();
      final response = await service.createResponse(
        CreateResponse.fromJson({'input': 'remember me'}),
      );

      final items = await service.listResponseInputItems(response.id);
      expect(items.data, hasLength(1));
      expect(items.data.single.toJson()['role'], 'user');

      expect(await service.deleteResponse(response.id), isTrue);
      expect(await service.getResponse(response.id), isNull);
    });
  });

  group('InMemoryResponsesService (streaming)', () {
    test('emits an ordered text event sequence', () async {
      final service = newService();
      final events = await service
          .createResponseStreaming(
            CreateResponse.fromJson({'model': 'gpt-4o', 'input': 'hi'}),
          )
          .toList();

      final types = events.map((e) => e.type).toList();
      expect(types.first, 'response.created');
      expect(types, contains('response.output_item.added'));
      expect(types, contains('response.output_text.delta'));
      expect(types, contains('response.output_text.done'));
      expect(types, contains('response.output_item.done'));
      expect(types.last, 'response.completed');

      // Sequence numbers are monotonically increasing from zero.
      for (var i = 0; i < events.length; i++) {
        expect(events[i].sequenceNumber, i);
      }

      // The text delta carries the echoed content.
      final delta = events.whereType<StreamingOutputTextDelta>().single;
      expect(delta.delta, 'echo: hi');

      // The response is retrievable and its events replay.
      final completed = events
          .whereType<StreamingResponseCompleted>()
          .single
          .response;
      final replay = await service.getResponseStreaming(completed.id).toList();
      expect(replay, isNotEmpty);
    });
  });

  group('ResponsesHandler', () {
    test('cancel on a terminal response is a 400', () async {
      final service = newService();
      final handler = ResponsesHandler(service);
      final response = await service.createResponse(
        CreateResponse.fromJson({'input': 'hi'}),
      );

      final result = await handler.cancelResponse(response.id);
      expect(result.statusCode, 400);
    });

    test('get on a missing response is a 404', () async {
      final handler = ResponsesHandler(newService());
      final result = await handler.getResponse('resp_missing');
      expect(result.statusCode, 404);
    });
  });
}

/// A minimal agent that echoes the last user message.
class _EchoAgent extends AIAgent {
  @override
  String? get name => 'echo';

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _EchoSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => '{}';

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _EchoSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async => AgentResponse(
    message: ChatMessage.fromText(ChatRole.assistant, _echo(messages)),
  );

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    yield AgentResponseUpdate(
      role: ChatRole.assistant,
      content: _echo(messages),
    );
  }

  String _echo(Iterable<ChatMessage> messages) => 'echo: ${messages.last.text}';
}

class _EchoSession extends AgentSession {
  _EchoSession() : super(AgentSessionStateBag(null));
}
