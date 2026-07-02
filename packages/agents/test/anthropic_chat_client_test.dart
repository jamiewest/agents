import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agents/agents.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:extensions/ai.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('AnthropicChatClient', () {
    test('builds Anthropic request from chat options and messages', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
        defaultMaxTokens: 123,
        betas: const ['test-beta'],
      );

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.system, 'System message'),
          ChatMessage.fromText(ChatRole.user, 'Hello'),
        ],
        options: ChatOptions(
          modelId: 'claude-option',
          instructions: 'Base instructions',
          temperature: 0.2,
          topP: 0.9,
          topK: 40,
          stopSequences: ['STOP'],
        ),
      );

      final request = httpClient.requests.single;
      expect(request.headers['anthropic-beta'], 'test-beta');
      expect(request.jsonBody['model'], 'claude-option');
      expect(request.jsonBody['max_tokens'], 123);
      expect(request.jsonBody['system'], 'Base instructions\n\nSystem message');
      expect(request.jsonBody['temperature'], 0.2);
      expect(request.jsonBody['top_p'], 0.9);
      expect(request.jsonBody['top_k'], 40);
      expect(request.jsonBody['stop_sequences'], ['STOP']);
      expect(request.jsonBody['stream'], isNull);
      expect(request.jsonBody['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Hello'},
          ],
        },
      ]);
    });

    test('maps tools and required tool choice', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'Use a tool')],
        options: ChatOptions(
          tools: [
            _TestFunction(
              name: 'lookup',
              description: 'Looks up a value.',
              parametersSchema: {
                'type': 'object',
                'properties': {
                  'query': {'type': 'string'},
                },
                'required': ['query'],
                'additionalProperties': false,
              },
            ),
          ],
          toolMode: ChatToolMode.requireSpecific('lookup'),
          allowMultipleToolCalls: false,
        ),
      );

      final body = httpClient.requests.single.jsonBody;
      expect(body['tools'], [
        {
          'name': 'lookup',
          'description': 'Looks up a value.',
          'input_schema': {
            'additionalProperties': false,
            'type': 'object',
            'properties': {
              'query': {'type': 'string'},
            },
            'required': ['query'],
          },
        },
      ]);
      expect(body['tool_choice'], {
        'type': 'tool',
        'name': 'lookup',
        'disable_parallel_tool_use': true,
      });
    });

    test('maps hosted web search to Anthropic built-in web search', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'Search the web')],
        options: ChatOptions(tools: [HostedWebSearchTool()]),
      );

      final body = httpClient.requests.single.jsonBody;
      expect(body['tools'], [
        {'type': 'web_search_20250305', 'name': 'web_search'},
      ]);
    });

    test('maps response text, tool calls, finish reason, and usage', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(
          _messageJson(
            stopReason: 'tool_use',
            content: [
              {'type': 'text', 'text': 'Calling lookup.'},
              {
                'type': 'tool_use',
                'id': 'toolu_1',
                'name': 'lookup',
                'input': {'query': 'dart'},
              },
            ],
            usage: {'input_tokens': 10, 'output_tokens': 5},
          ),
        ),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
      );

      expect(response.responseId, 'msg_1');
      expect(response.modelId, 'claude-test');
      expect(response.finishReason, ChatFinishReason.toolCalls);
      expect(response.usage!.inputTokenCount, 10);
      expect(response.usage!.outputTokenCount, 5);
      expect(response.usage!.totalTokenCount, 15);
      expect(response.rawRepresentation, isA<anthropic.Message>());

      final contents = response.messages.single.contents;
      expect((contents[0] as TextContent).text, 'Calling lookup.');
      final call = contents[1] as FunctionCallContent;
      expect(call.callId, 'toolu_1');
      expect(call.name, 'lookup');
      expect(call.arguments, {'query': 'dart'});
    });

    test('maps streaming text deltas and final usage update', () async {
      final httpClient = _FakeHttpClient([
        _sseResponse([
          _sse('message_start', {
            'type': 'message_start',
            'message': _messageJson(text: ''),
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hel'},
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'lo'},
          }),
          _sse('message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 2, 'input_tokens': 4},
          }),
          _sse('message_stop', {'type': 'message_stop'}),
        ]),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
          )
          .toList();

      expect(updates, hasLength(3));
      expect(updates[0].text, 'Hel');
      expect(updates[1].text, 'lo');
      expect(updates[2].finishReason, ChatFinishReason.stop);
      expect(updates[2].usage!.inputTokenCount, 4);
      expect(updates[2].usage!.outputTokenCount, 2);
      expect(updates[2].rawRepresentation, isA<anthropic.MessageDeltaEvent>());
      expect(httpClient.requests.single.jsonBody['stream'], isTrue);
    });

    test('maps streaming text, tool calls, and final usage update', () async {
      final httpClient = _FakeHttpClient([
        _sseResponse([
          _sse('message_start', {
            'type': 'message_start',
            'message': _messageJson(text: ''),
          }),
          _sse('content_block_start', {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Calling lookup.'},
          }),
          _sse('content_block_stop', {
            'type': 'content_block_stop',
            'index': 0,
          }),
          _sse('content_block_start', {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'lookup',
              'input': <String, Object?>{},
            },
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': '{"query":'},
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': '"dart"}'},
          }),
          _sse('content_block_stop', {
            'type': 'content_block_stop',
            'index': 1,
          }),
          _sse('message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 7, 'input_tokens': 12},
          }),
          _sse('message_stop', {'type': 'message_stop'}),
        ]),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
          )
          .toList();

      expect(updates, hasLength(3));
      expect(updates[0].text, 'Calling lookup.');

      final call = updates[1].contents.single as FunctionCallContent;
      expect(call.callId, 'toolu_1');
      expect(call.name, 'lookup');
      expect(call.arguments, {'query': 'dart'});
      expect(call.exception, isNull);
      expect(call.rawRepresentation, isA<anthropic.ToolUseBlock>());
      expect(
        updates[1].rawRepresentation,
        isA<anthropic.ContentBlockStopEvent>(),
      );

      expect(updates[2].finishReason, ChatFinishReason.toolCalls);
      expect(updates[2].usage!.inputTokenCount, 12);
      expect(updates[2].usage!.outputTokenCount, 7);
      expect(httpClient.requests.single.jsonBody['stream'], isTrue);
    });

    test('streams thinking deltas and a trailing signature', () async {
      final httpClient = _FakeHttpClient([
        _sseResponse([
          _sse('message_start', {
            'type': 'message_start',
            'message': _messageJson(text: ''),
          }),
          _sse('content_block_start', {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'thinking',
              'thinking': '',
              'signature': '',
            },
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': 'Pondering'},
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': ' deeply.'},
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'signature_delta', 'signature': 'sig_abc'},
          }),
          _sse('content_block_stop', {
            'type': 'content_block_stop',
            'index': 0,
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'text_delta', 'text': 'Answer.'},
          }),
          _sse('message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 3, 'input_tokens': 6},
          }),
          _sse('message_stop', {'type': 'message_stop'}),
        ]),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
          )
          .toList();

      final reasoning = updates
          .expand((u) => u.contents)
          .whereType<TextReasoningContent>()
          .toList();
      expect(reasoning.map((r) => r.text).join(), 'Pondering deeply.');
      expect(reasoning.last.additionalProperties?['signature'], 'sig_abc');
      expect(
        updates
            .expand((u) => u.contents)
            .whereType<TextContent>()
            .map((c) => c.text)
            .join(),
        'Answer.',
      );
    });

    test('serializes thinking history back as thinking blocks', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.user, 'Hello'),
          ChatMessage(
            role: ChatRole.assistant,
            contents: [
              TextReasoningContent('Pondering'),
              TextReasoningContent(
                ' deeply.',
                additionalProperties: {'signature': 'sig_abc'},
              ),
              TextContent('Answer.'),
            ],
          ),
          ChatMessage.fromText(ChatRole.user, 'And?'),
        ],
      );

      final messages = httpClient.requests.single.jsonBody['messages'] as List;
      final assistant = (messages[1] as Map)['content'] as List;
      expect(assistant.first, {
        'type': 'thinking',
        'thinking': 'Pondering deeply.',
        'signature': 'sig_abc',
      });
      expect((assistant[1] as Map)['type'], 'text');
    });

    test('drops unsigned reasoning instead of throwing', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.user, 'Hello'),
          ChatMessage(
            role: ChatRole.assistant,
            contents: [
              TextReasoningContent('No signature here.'),
              TextContent('Answer.'),
            ],
          ),
          ChatMessage.fromText(ChatRole.user, 'And?'),
        ],
      );

      final messages = httpClient.requests.single.jsonBody['messages'] as List;
      final assistant = (messages[1] as Map)['content'] as List;
      expect(assistant, hasLength(1));
      expect((assistant.single as Map)['type'], 'text');
    });

    test('orders tool results before text in user messages', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.user, 'Hello'),
          ChatMessage(
            role: ChatRole.assistant,
            contents: [
              FunctionCallContent(
                callId: 'toolu_1',
                name: 'lookup',
                arguments: const {'query': 'dart'},
              ),
            ],
          ),
          ChatMessage(
            role: ChatRole.tool,
            contents: [
              TextContent('Some commentary.'),
              FunctionResultContent(callId: 'toolu_1', result: 'found'),
            ],
          ),
        ],
      );

      final messages = httpClient.requests.single.jsonBody['messages'] as List;
      final toolTurn = (messages[2] as Map)['content'] as List;
      expect((toolTurn.first as Map)['type'], 'tool_result');
      expect((toolTurn[1] as Map)['type'], 'text');
    });

    test('filters empty text blocks and skips empty messages', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.user, 'Hello'),
          ChatMessage(role: ChatRole.assistant, contents: [TextContent('   ')]),
          ChatMessage(
            role: ChatRole.user,
            contents: [TextContent(''), TextContent('Still there?')],
          ),
        ],
      );

      final messages = httpClient.requests.single.jsonBody['messages'] as List;
      expect(messages, hasLength(2));
      final second = (messages[1] as Map)['content'] as List;
      expect(second, hasLength(1));
      expect((second.single as Map)['text'], 'Still there?');
    });

    test('sends image DataContent as a base64 image block', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_messageJson(text: 'ok')),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.user,
            contents: [
              TextContent('What is this?'),
              DataContent(bytes, mediaType: 'image/png'),
            ],
          ),
        ],
      );

      final messages = httpClient.requests.single.jsonBody['messages'] as List;
      final content = (messages.single as Map)['content'] as List;
      final image = content[1] as Map;
      expect(image['type'], 'image');
      expect((image['source'] as Map)['type'], 'base64');
      expect((image['source'] as Map)['media_type'], 'image/png');
      expect((image['source'] as Map)['data'], base64Encode(bytes));
    });

    test('merges message_start usage into the delta usage', () async {
      final httpClient = _FakeHttpClient([
        _sseResponse([
          _sse('message_start', {
            'type': 'message_start',
            'message': _messageJson(
              text: '',
              usage: {
                'input_tokens': 42,
                'output_tokens': 0,
                'cache_read_input_tokens': 7,
              },
            ),
          }),
          _sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hi'},
          }),
          _sse('message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 2},
          }),
          _sse('message_stop', {'type': 'message_stop'}),
        ]),
      ]);
      final client = AnthropicChatClient(
        _anthropicClient(httpClient),
        modelId: 'claude-default',
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
          )
          .toList();

      final usage = updates.last.usage!;
      expect(usage.inputTokenCount, 42);
      expect(usage.outputTokenCount, 2);
      expect(usage.totalTokenCount, 44);
      expect(usage.cachedInputTokenCount, 7);
    });

    test('AnthropicClient.asAIAgent applies settings and factory', () {
      final anthropicClient = _anthropicClient(_FakeHttpClient([]));
      var factoryCalled = false;

      final agent = anthropicClient.asAIAgent(
        modelId: 'claude-default',
        instructions: 'Instructions',
        name: 'ClaudeAgent',
        description: 'Anthropic-backed agent',
        tools: [_TestFunction(name: 'lookup')],
        clientFactory: (innerClient) {
          factoryCalled = true;
          expect(innerClient, isA<AnthropicChatClient>());
          return innerClient;
        },
      );

      expect(factoryCalled, isTrue);
      expect(agent.name, 'ClaudeAgent');
      expect(agent.description, 'Anthropic-backed agent');
      expect(agent.instructions, 'Instructions');
      expect(agent.chatOptions!.tools, hasLength(1));
    });
  });
}

anthropic.AnthropicClient _anthropicClient(http.Client httpClient) {
  return anthropic.AnthropicClient(
    config: const anthropic.AnthropicConfig(
      authProvider: anthropic.ApiKeyProvider('test-key'),
      baseUrl: 'https://anthropic.test',
      retryPolicy: anthropic.RetryPolicy(maxRetries: 0),
    ),
    httpClient: httpClient,
  );
}

Map<String, Object?> _messageJson({
  String text = 'ok',
  String stopReason = 'end_turn',
  List<Map<String, Object?>>? content,
  Map<String, Object?> usage = const {'input_tokens': 1, 'output_tokens': 1},
}) {
  return {
    'id': 'msg_1',
    'type': 'message',
    'role': 'assistant',
    'content':
        content ??
        [
          {'type': 'text', 'text': text},
        ],
    'model': 'claude-test',
    'stop_reason': stopReason,
    'usage': usage,
  };
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _sseResponse(List<String> events) {
  return http.Response(
    events.join(),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

String _sse(String event, Map<String, Object?> data) {
  return 'event: $event\n'
      'data: ${jsonEncode(data)}\n\n';
}

final class _RecordedRequest {
  _RecordedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  Map<String, dynamic> get jsonBody => jsonDecode(body) as Map<String, dynamic>;
}

final class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(List<http.Response> responses)
    : _responses = Queue.of(responses);

  final Queue<http.Response> _responses;
  final requests = <_RecordedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request
        ? request.body
        : await request.finalize().bytesToString();
    requests.add(
      _RecordedRequest(
        method: request.method,
        url: request.url,
        headers: Map.of(request.headers),
        body: body,
      ),
    );

    if (_responses.isEmpty) {
      throw StateError('No fake response queued for ${request.url}.');
    }

    final response = _responses.removeFirst();
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

final class _TestFunction extends AIFunctionDeclaration {
  _TestFunction({
    required super.name,
    super.description,
    super.parametersSchema,
  });
}
