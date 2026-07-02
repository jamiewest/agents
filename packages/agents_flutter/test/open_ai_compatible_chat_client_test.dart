// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class _Declaration extends AIFunctionDeclaration {
  _Declaration({
    required super.name,
    super.description,
    super.parametersSchema,
  });
}

/// Builds a wrapper around a real `OpenAIChatClient` whose transport is
/// faked: non-streaming requests get [completion], streaming requests get
/// [chunks] as SSE. The last JSON request body is captured into
/// [requests].
OpenAICompatibleChatClient _client({
  OpenAIModelProfile profile = const OpenAIModelProfile(),
  Map<String, dynamic>? completion,
  List<Map<String, dynamic>>? chunks,
  List<Map<String, dynamic>>? requests,
}) {
  final handler = MockClient.streaming((request, bodyStream) async {
    final body = await utf8.decodeStream(bodyStream);
    requests?.add(jsonDecode(body) as Map<String, dynamic>);
    final isStream =
        (jsonDecode(body) as Map<String, dynamic>)['stream'] == true;
    if (isStream) {
      final sse = [
        for (final chunk in chunks ?? const <Map<String, dynamic>>[])
          'data: ${jsonEncode(chunk)}\n',
        'data: [DONE]\n',
      ].join('\n');
      return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(completion ?? _completion()))),
      200,
    );
  });
  return OpenAICompatibleChatClient(
    OpenAIChatClient(
      'test-model',
      'key',
      options: OpenAIClientOptions(httpClient: handler),
    ),
    profile: profile,
  );
}

Map<String, dynamic> _completion({
  Map<String, dynamic>? message,
  String finishReason = 'stop',
}) => {
  'id': 'resp_1',
  'model': 'test-model',
  'choices': [
    {
      'message': message ?? {'role': 'assistant', 'content': 'Hello.'},
      'finish_reason': finishReason,
    },
  ],
};

Map<String, dynamic> _chunk({
  Map<String, dynamic> delta = const {},
  String? finishReason,
}) => {
  'id': 'resp_1',
  'model': 'test-model',
  'choices': [
    {'delta': delta, 'finish_reason': finishReason},
  ],
};

void main() {
  final weather = _Declaration(
    name: 'get_weather',
    description: 'Gets the weather.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'location': {'type': 'string'},
      },
    },
  );

  final userMessage = ChatMessage.fromText(ChatRole.user, 'Weather in SF?');

  group('native mode: request body', () {
    test('sends tools and tool_choice', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(requests: requests);

      await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(
          tools: [weather],
          toolMode: ChatToolMode.requireAny,
        ),
      );

      final body = requests.single;
      final tools = body['tools'] as List;
      expect(tools, hasLength(1));
      expect(((tools.single as Map)['function'] as Map)['name'], 'get_weather');
      expect(body['tool_choice'], 'required');
      expect(body.containsKey('parallel_tool_calls'), isFalse);
    });

    test('maps a required function name', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(requests: requests);

      await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(
          tools: [weather],
          toolMode: const RequiredChatToolMode(
            requiredFunctionName: 'get_weather',
          ),
        ),
      );

      expect(requests.single['tool_choice'], {
        'type': 'function',
        'function': {'name': 'get_weather'},
      });
    });

    test('disables parallel calls from the profile', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(
        profile: const OpenAIModelProfile(parallelToolCalls: false),
        requests: requests,
      );

      await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(tools: [weather]),
      );

      expect(requests.single['parallel_tool_calls'], isFalse);
    });

    test('caller raw representation keys win', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(requests: requests);

      await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(
          tools: [weather],
          rawRepresentationFactory: (_) => {'tools': 'caller-owned'},
        ),
      );

      expect(requests.single['tools'], 'caller-owned');
    });

    test('sends no tools when the profile disables them', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(
        profile: const OpenAIModelProfile(toolMode: ToolCallingMode.none),
        requests: requests,
      );

      await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(tools: [weather]),
      );

      expect(requests.single.containsKey('tools'), isFalse);
    });

    test('JSON-encodes structured tool results', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(requests: requests);

      await client.getResponse(
        messages: [
          userMessage,
          ChatMessage(
            role: ChatRole.assistant,
            contents: [
              FunctionCallContent(
                callId: 'call_1',
                name: 'get_weather',
                arguments: const {'location': 'SF'},
              ),
            ],
          ),
          ChatMessage(
            role: ChatRole.tool,
            contents: [
              FunctionResultContent(
                callId: 'call_1',
                name: 'get_weather',
                result: const {'temperature': 55},
              ),
            ],
          ),
        ],
        options: ChatOptions(tools: [weather]),
      );

      final messages = requests.single['messages'] as List;
      final toolMessage = messages.cast<Map<String, dynamic>>().singleWhere(
        (m) => m['role'] == 'tool',
      );
      expect(jsonDecode(toolMessage['content'] as String), {'temperature': 55});
    });

    test('splits assistant messages mixing text and calls', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(requests: requests);

      await client.getResponse(
        messages: [
          userMessage,
          ChatMessage(
            role: ChatRole.assistant,
            contents: [
              TextContent('Let me check.'),
              FunctionCallContent(
                callId: 'call_1',
                name: 'get_weather',
                arguments: const {'location': 'SF'},
              ),
            ],
          ),
        ],
        options: ChatOptions(tools: [weather]),
      );

      final messages = (requests.single['messages'] as List)
          .cast<Map<String, dynamic>>();
      final assistant = messages
          .where((m) => m['role'] == 'assistant')
          .toList();
      expect(assistant, hasLength(2));
      expect(assistant[0]['content'], 'Let me check.');
      expect(assistant[1]['tool_calls'], isNotNull);
    });
  });

  group('native mode: streaming', () {
    test('assembles tool_calls split across chunks', () async {
      final client = _client(
        chunks: [
          _chunk(
            delta: {
              'role': 'assistant',
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_abc',
                  'type': 'function',
                  'function': {'name': 'get_weather', 'arguments': '{"loc'},
                },
              ],
            },
          ),
          _chunk(
            delta: {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': 'ation": "SF"}'},
                },
              ],
            },
          ),
          _chunk(finishReason: 'tool_calls'),
        ],
      );

      final updates = await client
          .getStreamingResponse(
            messages: [userMessage],
            options: ChatOptions(tools: [weather]),
          )
          .toList();

      final calls = updates
          .expand((u) => u.contents)
          .whereType<FunctionCallContent>()
          .toList();
      expect(calls, hasLength(1));
      expect(calls.single.callId, 'call_abc');
      expect(calls.single.name, 'get_weather');
      expect(calls.single.arguments, {'location': 'SF'});
      expect(
        updates.any((u) => u.finishReason == ChatFinishReason.toolCalls),
        isTrue,
      );
    });

    test('keeps parallel calls separate by index', () async {
      final client = _client(
        chunks: [
          _chunk(
            delta: {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_a',
                  'function': {'name': 'get_weather', 'arguments': ''},
                },
                {
                  'index': 1,
                  'id': 'call_b',
                  'function': {'name': 'get_weather', 'arguments': ''},
                },
              ],
            },
          ),
          _chunk(
            delta: {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '{"location": "SF"}'},
                },
                {
                  'index': 1,
                  'function': {'arguments': '{"location": "NYC"}'},
                },
              ],
            },
          ),
          _chunk(finishReason: 'tool_calls'),
        ],
      );

      final updates = await client
          .getStreamingResponse(
            messages: [userMessage],
            options: ChatOptions(tools: [weather]),
          )
          .toList();

      final calls = updates
          .expand((u) => u.contents)
          .whereType<FunctionCallContent>()
          .toList();
      expect(calls, hasLength(2));
      expect(calls[0].arguments, {'location': 'SF'});
      expect(calls[1].arguments, {'location': 'NYC'});
    });

    test('malformed streamed arguments attach an exception', () async {
      final client = _client(
        chunks: [
          _chunk(
            delta: {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_a',
                  'function': {'name': 'get_weather', 'arguments': '{bad'},
                },
              ],
            },
          ),
          _chunk(finishReason: 'tool_calls'),
        ],
      );

      final updates = await client
          .getStreamingResponse(
            messages: [userMessage],
            options: ChatOptions(tools: [weather]),
          )
          .toList();

      final call = updates
          .expand((u) => u.contents)
          .whereType<FunctionCallContent>()
          .single;
      expect(call.arguments, isNull);
      expect(call.exception, isNotNull);
    });

    test('recovers reasoning delta fields', () async {
      final client = _client(
        chunks: [
          _chunk(delta: {'reasoning': 'Thinking about SF.'}),
          _chunk(delta: {'content': 'It is sunny.'}),
          _chunk(finishReason: 'stop'),
        ],
      );

      final updates = await client
          .getStreamingResponse(messages: [userMessage])
          .toList();

      expect(
        updates
            .expand((u) => u.contents)
            .whereType<TextReasoningContent>()
            .map((c) => c.text)
            .join(),
        'Thinking about SF.',
      );
      expect(
        updates
            .expand((u) => u.contents)
            .whereType<TextContent>()
            .map((c) => c.text)
            .join(),
        'It is sunny.',
      );
    });

    test('splits <think> tags across chunk boundaries', () async {
      final client = _client(
        profile: const OpenAIModelProfile(
          reasoningTags: ReasoningTagStyle.thinkTags,
        ),
        chunks: [
          _chunk(delta: {'content': '<thi'}),
          _chunk(delta: {'content': 'nk>hmm</think>Sunny'}),
          _chunk(delta: {'content': ', 65F.'}),
          _chunk(finishReason: 'stop'),
        ],
      );

      final updates = await client
          .getStreamingResponse(messages: [userMessage])
          .toList();

      expect(
        updates
            .expand((u) => u.contents)
            .whereType<TextReasoningContent>()
            .map((c) => c.text)
            .join(),
        'hmm',
      );
      expect(
        updates
            .expand((u) => u.contents)
            .whereType<TextContent>()
            .map((c) => c.text)
            .join(),
        'Sunny, 65F.',
      );
    });
  });

  group('native mode: non-streaming response', () {
    test('recovers assistant text dropped alongside tool_calls', () async {
      final client = _client(
        completion: _completion(
          message: {
            'role': 'assistant',
            'content': 'Let me check.',
            'tool_calls': [
              {
                'id': 'call_a',
                'type': 'function',
                'function': {
                  'name': 'get_weather',
                  'arguments': '{"location": "SF"}',
                },
              },
            ],
          },
          finishReason: 'tool_calls',
        ),
      );

      final response = await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(tools: [weather]),
      );

      final contents = response.messages.single.contents;
      expect(contents.whereType<TextContent>().single.text, 'Let me check.');
      expect(contents.whereType<FunctionCallContent>(), hasLength(1));
      expect(response.finishReason, ChatFinishReason.toolCalls);
    });

    test('recovers a reasoning field', () async {
      final client = _client(
        completion: _completion(
          message: {
            'role': 'assistant',
            'content': 'Sunny.',
            'reasoning': 'Considered the forecast.',
          },
        ),
      );

      final response = await client.getResponse(messages: [userMessage]);
      final contents = response.messages.single.contents;
      expect(
        contents.whereType<TextReasoningContent>().single.text,
        'Considered the forecast.',
      );
    });
  });

  group('prompt-injected mode', () {
    const profile = OpenAIModelProfile(
      toolMode: ToolCallingMode.promptInjected,
      fallbackFormatName: 'qwen',
    );

    test('moves tools into the system message', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(profile: profile, requests: requests);

      await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(instructions: 'Be helpful.', tools: [weather]),
      );

      final body = requests.single;
      expect(body.containsKey('tools'), isFalse);
      final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
      final system = messages.firstWhere((m) => m['role'] == 'system');
      expect(system['content'], contains('Be helpful.'));
      expect(system['content'], contains('<tools>'));
      expect(system['content'], contains('get_weather'));
    });

    test('rewrites past calls and results as text', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(profile: profile, requests: requests);

      await client.getResponse(
        messages: [
          userMessage,
          ChatMessage(
            role: ChatRole.assistant,
            contents: [
              FunctionCallContent(
                callId: 'call_1',
                name: 'get_weather',
                arguments: const {'location': 'SF'},
              ),
            ],
          ),
          ChatMessage(
            role: ChatRole.tool,
            contents: [
              FunctionResultContent(callId: 'call_1', result: 'sunny'),
            ],
          ),
        ],
        options: ChatOptions(tools: [weather]),
      );

      final messages = (requests.single['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages.every((m) => m['role'] != 'tool'), isTrue);
      final assistant = messages.firstWhere((m) => m['role'] == 'assistant');
      expect(assistant['content'], contains('<tool_call>'));
      final results = messages
          .where(
            (m) =>
                m['role'] == 'user' &&
                (m['content'] as String).contains('<tool_response>'),
          )
          .toList();
      expect(results, hasLength(1));
      expect(results.single['content'], contains('sunny'));
    });

    test(
      'parses a streamed tool call and synthesizes the finish reason',
      () async {
        final client = _client(
          profile: profile,
          chunks: [
            _chunk(delta: {'role': 'assistant', 'content': 'Checking '}),
            _chunk(delta: {'content': 'now. <tool_call>{"name": '}),
            _chunk(
              delta: {
                'content':
                    '"get_weather", "arguments": {"location": "SF"}}</tool_call>',
              },
            ),
            _chunk(finishReason: 'stop'),
          ],
        );

        final updates = await client
            .getStreamingResponse(
              messages: [userMessage],
              options: ChatOptions(tools: [weather]),
            )
            .toList();

        final calls = updates
            .expand((u) => u.contents)
            .whereType<FunctionCallContent>()
            .toList();
        expect(calls, hasLength(1));
        expect(calls.single.name, 'get_weather');
        expect(calls.single.arguments, {'location': 'SF'});
        expect(updates.last.finishReason, ChatFinishReason.toolCalls);
        expect(
          updates
              .expand((u) => u.contents)
              .whereType<TextContent>()
              .map((c) => c.text)
              .join()
              .trim(),
          'Checking now.',
        );
      },
    );

    test('parses a non-streaming tool call', () async {
      final client = _client(
        profile: profile,
        completion: _completion(
          message: {
            'role': 'assistant',
            'content':
                '<tool_call>{"name": "get_weather", '
                '"arguments": {"location": "SF"}}</tool_call>',
          },
        ),
      );

      final response = await client.getResponse(
        messages: [userMessage],
        options: ChatOptions(tools: [weather]),
      );

      final call = response.messages.single.contents
          .whereType<FunctionCallContent>()
          .single;
      expect(call.name, 'get_weather');
      expect(response.finishReason, ChatFinishReason.toolCalls);
    });

    test('malformed streamed call falls back to text', () async {
      final client = _client(
        profile: profile,
        chunks: [
          _chunk(delta: {'content': '<tool_call>{oops'}),
          _chunk(finishReason: 'stop'),
        ],
      );

      final updates = await client
          .getStreamingResponse(
            messages: [userMessage],
            options: ChatOptions(tools: [weather]),
          )
          .toList();

      expect(
        updates.expand((u) => u.contents).whereType<FunctionCallContent>(),
        isEmpty,
      );
      expect(
        updates
            .expand((u) => u.contents)
            .whereType<TextContent>()
            .map((c) => c.text)
            .join(),
        '<tool_call>{oops',
      );
      expect(updates.last.finishReason, ChatFinishReason.stop);
    });

    test('without tools the request passes through natively', () async {
      final requests = <Map<String, dynamic>>[];
      final client = _client(profile: profile, requests: requests);

      await client.getResponse(messages: [userMessage]);

      final messages = (requests.single['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages.any((m) => m['role'] == 'system'), isFalse);
    });
  });
}
