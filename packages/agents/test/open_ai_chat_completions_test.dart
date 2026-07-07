// Copyright (c) Microsoft. All rights reserved.

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/hosting/open_ai/chat_completions/ai_agent_chat_completions_processor.dart';
import 'package:agents/src/hosting/open_ai/chat_completions/models/create_chat_completion.dart';
import 'package:agents/src/hosting/open_ai/id_generator.dart';
import 'package:agents/src/hosting/open_ai/models/sort_order.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('SortOrder', () {
    test('round-trips wire values', () {
      expect(SortOrder.fromJson('asc'), SortOrder.ascending);
      expect(SortOrder.fromJson('DESC'), SortOrder.descending);
      expect(SortOrder.ascending.toJson(), 'asc');
      expect(SortOrder.descending.toJson(), 'desc');
    });

    test('rejects null and unknown values', () {
      expect(() => SortOrder.fromJson(null), throwsFormatException);
      expect(() => SortOrder.fromJson('sideways'), throwsFormatException);
    });
  });

  group('IdGenerator', () {
    test('generated IDs share the conversation partition key', () {
      final gen = IdGenerator(randomSeed: 7);
      final a = gen.generateMessageId();
      final b = gen.generateFunctionCallId();

      // Last 16 characters (the partition key) match across IDs.
      expect(a.substring(a.length - 16), b.substring(b.length - 16));
      expect(a, startsWith('msg_'));
      expect(b, startsWith('func_'));
    });

    test('newId honors prefix and delimiter', () {
      final id = IdGenerator.newId(
        'chatcmpl',
        delimiter: '-',
        stringLength: 13,
      );
      expect(id, startsWith('chatcmpl-'));
    });
  });

  group('CreateChatCompletion.fromJson', () {
    test('parses a simple text request', () {
      final request = CreateChatCompletion.fromJson({
        'model': 'gpt-4o',
        'messages': [
          {'role': 'user', 'content': 'Hello'},
        ],
      });

      expect(request.model, 'gpt-4o');
      expect(request.messages, hasLength(1));
      final message = request.messages.single.toChatMessage();
      expect(message.role, ChatRole.user);
      expect(message.text, 'Hello');
    });
  });

  group('AIAgentChatCompletionsProcessor', () {
    test('non-streaming completion echoes the agent response', () async {
      final agent = _EchoAgent();
      final request = CreateChatCompletion.fromJson({
        'model': 'gpt-4o',
        'messages': [
          {'role': 'user', 'content': 'Hi there'},
        ],
        'service_tier': 'flex',
      });

      final completion =
          await AIAgentChatCompletionsProcessor.createChatCompletion(
            agent,
            request,
          );
      final json = completion.toJson();

      expect(json['object'], 'chat.completion');
      expect(json['model'], 'gpt-4o');
      expect(json['service_tier'], 'flex');
      final choices = json['choices'] as List;
      expect(choices, hasLength(1));
      final message = (choices.single as Map)['message'] as Map;
      expect(message['role'], 'assistant');
      expect(message['content'], 'echo: Hi there');
    });

    test('streaming completion yields chunks', () async {
      final agent = _EchoAgent();
      final request = CreateChatCompletion.fromJson({
        'model': 'gpt-4o',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'stream me'},
        ],
      });

      final chunks = await AIAgentChatCompletionsProcessor.streamChatCompletion(
        agent,
        request,
      ).toList();

      expect(chunks, isNotEmpty);
      final first = chunks.first.toJson();
      expect(first['object'], 'chat.completion.chunk');
      final delta = ((first['choices'] as List).first as Map)['delta'] as Map;
      expect(delta['content'], 'echo: stream me');
      expect(delta['role'], 'assistant');
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
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => '{}';

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _EchoSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, _echo(messages)),
    );
  }

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
