// Copyright (c) Microsoft. All rights reserved.

import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAIChatClient.asAIAgent', () {
    test('creates a ChatClientAgent', () {
      final client = OpenAIChatClient('gpt-test', 'test-key');

      final agent = client.asAIAgent(name: 'openai-agent');

      expect(agent, isA<ChatClientAgent>());
      expect(agent.name, 'openai-agent');
    });

    test('chatClientFactory wraps the underlying client', () {
      final client = OpenAIChatClient('gpt-test', 'test-key');
      late _WrapperChatClient wrapper;

      final agent = client.asAIAgent(
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
        chatClientFactory: (inner) {
          wrapper = _WrapperChatClient(inner);
          return wrapper;
        },
      );

      expect(agent.chatClient, same(wrapper));
      expect(wrapper.innerClient, same(client));
    });

    test('translates convenience settings into agent options', () {
      final client = OpenAIChatClient('gpt-test', 'test-key');
      final tools = [_TestTool()];

      final agent = client.asAIAgent(
        instructions: 'Be concise.',
        name: 'helper',
        description: 'Answers briefly.',
        tools: tools,
      );

      expect(agent.name, 'helper');
      expect(agent.description, 'Answers briefly.');
      expect(agent.instructions, 'Be concise.');
      expect(agent.chatOptions!.tools, hasLength(1));
      expect(agent.chatOptions!.tools!.single, same(tools.single));
    });

    test('explicit options win over convenience settings', () {
      final client = OpenAIChatClient('gpt-test', 'test-key');
      final options = ChatClientAgentOptions()
        ..name = 'from-options'
        ..description = 'option description'
        ..chatOptions = ChatOptions(instructions: 'option instructions');

      final agent = client.asAIAgent(
        options: options,
        name: 'from-parameter',
        description: 'parameter description',
        instructions: 'parameter instructions',
      );

      expect(agent.name, 'from-options');
      expect(agent.description, 'option description');
      expect(agent.instructions, 'option instructions');
    });
  });

  group('OpenAIAgentResponseExtensions', () {
    test('returns raw chat completion map when present', () {
      final raw = {
        'id': 'chatcmpl_raw',
        'object': 'chat.completion',
        'choices': const [],
      };
      final response = AgentResponse(
        response: ChatResponse(rawRepresentation: raw),
      );

      expect(response.asOpenAIChatCompletion(), same(raw));
    });

    test('generates a chat completion map from a plain response', () {
      final response = AgentResponse(
        response: ChatResponse(
          messages: [ChatMessage.fromText(ChatRole.assistant, 'hello')],
          responseId: 'chatcmpl_1',
          modelId: 'gpt-test',
          createdAt: DateTime.utc(2024),
          finishReason: ChatFinishReason.stop,
          usage: UsageDetails(
            inputTokenCount: 3,
            outputTokenCount: 4,
            totalTokenCount: 7,
          ),
        ),
      );

      final json = response.asOpenAIChatCompletion();

      expect(json['id'], 'chatcmpl_1');
      expect(json['object'], 'chat.completion');
      expect(json['created'], 1704067200);
      expect(json['model'], 'gpt-test');
      final choice = (json['choices'] as List).single as Map;
      expect(choice['finish_reason'], 'stop');
      expect((choice['message'] as Map)['content'], 'hello');
      expect(json['usage'], {
        'prompt_tokens': 3,
        'completion_tokens': 4,
        'total_tokens': 7,
      });
    });

    test('streaming chat updates convert text deltas and usage', () async {
      final updates = Stream.fromIterable([
        AgentResponseUpdate(
          chatResponseUpdate: ChatResponseUpdate(
            role: ChatRole.assistant,
            contents: [TextContent('hi')],
            responseId: 'chatcmpl_1',
            modelId: 'gpt-test',
            createdAt: DateTime.utc(2024),
          ),
        ),
        AgentResponseUpdate(
          chatResponseUpdate: ChatResponseUpdate(
            responseId: 'chatcmpl_1',
            modelId: 'gpt-test',
            usage: UsageDetails(
              inputTokenCount: 1,
              outputTokenCount: 2,
              totalTokenCount: 3,
            ),
          ),
        ),
      ]);

      final chunks = await updates
          .asOpenAIStreamingChatCompletionUpdates()
          .toList();

      expect(chunks, hasLength(2));
      expect(chunks.first['object'], 'chat.completion.chunk');
      final choice = (chunks.first['choices'] as List).single as Map;
      expect(choice['delta'], {'role': 'assistant', 'content': 'hi'});
      expect(chunks.last['choices'], isEmpty);
      expect(chunks.last['usage'], {
        'prompt_tokens': 1,
        'completion_tokens': 2,
        'total_tokens': 3,
      });
    });

    test('responses streaming skips unsupported non-raw updates', () async {
      final raw = {
        'type': 'response.output_text.delta',
        'sequence_number': 1,
        'delta': 'ok',
      };
      final rawUpdate = AgentResponseUpdate(content: 'raw');
      rawUpdate.rawRepresentation = raw;

      final events = await Stream.fromIterable([
        AgentResponseUpdate(content: 'plain'),
        rawUpdate,
      ]).asOpenAIStreamingResponseUpdates().toList();

      expect(events, [same(raw)]);
    });
  });
}

class _WrapperChatClient extends DelegatingChatClient {
  _WrapperChatClient(super.innerClient);
}

class _TestTool extends AITool {
  _TestTool() : super(name: 'test_tool', description: 'A test tool.');
}
