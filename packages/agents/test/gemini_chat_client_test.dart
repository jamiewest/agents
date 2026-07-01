import 'dart:collection';
import 'dart:convert';

import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('GeminiChatClient', () {
    test('builds Gemini request from chat options and messages', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_responseJson(text: 'ok')),
      ]);
      final client = GeminiChatClient(
        _geminiClient(httpClient),
        modelId: 'gemini-default',
      );

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.system, 'System message'),
          ChatMessage.fromText(ChatRole.user, 'Hello'),
        ],
        options: ChatOptions(
          modelId: 'gemini-option',
          instructions: 'Base instructions',
          temperature: 0.2,
          topP: 0.9,
          topK: 40,
          maxOutputTokens: 123,
          stopSequences: ['STOP'],
          responseFormat: ChatResponseFormat.json,
        ),
      );

      final request = httpClient.requests.single;
      expect(request.url.path, '/v1beta/models/gemini-option:generateContent');
      expect(request.headers['x-goog-api-key'], 'test-key');
      expect(request.jsonBody['systemInstruction'], {
        'parts': [
          {'text': 'Base instructions\n\nSystem message'},
        ],
      });
      expect(request.jsonBody['generationConfig'], {
        'temperature': 0.2,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 123,
        'stopSequences': ['STOP'],
        'responseMimeType': 'application/json',
      });
      expect(request.jsonBody['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'Hello'},
          ],
        },
      ]);
    });

    test('maps tools, hosted web search, and required tool choice', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_responseJson(text: 'ok')),
      ]);
      final client = GeminiChatClient(
        _geminiClient(httpClient),
        modelId: 'gemini-default',
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
                  'query': {'type': 'string', 'additionalProperties': false},
                },
                'required': ['query'],
                'additionalProperties': false,
              },
            ),
            HostedWebSearchTool(),
          ],
          toolMode: ChatToolMode.requireSpecific('lookup'),
        ),
      );

      final body = httpClient.requests.single.jsonBody;
      expect(body['tools'], [
        {
          'functionDeclarations': [
            {
              'name': 'lookup',
              'description': 'Looks up a value.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'query': {'type': 'string'},
                },
                'required': ['query'],
              },
            },
          ],
        },
        {'googleSearch': <String, Object?>{}},
      ]);
      expect(body['toolConfig'], {
        'functionCallingConfig': {
          'mode': 'ANY',
          'allowedFunctionNames': ['lookup'],
        },
        'includeServerSideToolInvocations': true,
      });
    });

    test(
      'omits includeServerSideToolInvocations when tools are not mixed',
      () async {
        final httpClient = _FakeHttpClient([
          _jsonResponse(_responseJson(text: 'ok')),
        ]);
        final client = GeminiChatClient(
          _geminiClient(httpClient),
          modelId: 'gemini-default',
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
                },
              ),
            ],
          ),
        );

        final body = httpClient.requests.single.jsonBody;
        expect(body.containsKey('toolConfig'), isFalse);
      },
    );

    test('strips additionalProperties from responseSchema', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_responseJson(text: 'ok')),
      ]);
      final client = GeminiChatClient(
        _geminiClient(httpClient),
        modelId: 'gemini-default',
      );

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
        options: ChatOptions(
          responseFormat: ChatResponseFormat.forJsonSchema(
            schemaName: 'verdict',
            schema: {
              'type': 'object',
              'properties': {
                'answered': {'type': 'boolean'},
              },
              'required': ['answered'],
              'additionalProperties': false,
            },
          ),
        ),
      );

      final body = httpClient.requests.single.jsonBody;
      expect(body['generationConfig']['responseSchema'], {
        'type': 'object',
        'properties': {
          'answered': {'type': 'boolean'},
        },
        'required': ['answered'],
      });
    });

    test('maps response text, tool calls, finish reason, and usage', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(
          _responseJson(
            finishReason: 'STOP',
            parts: [
              {'text': 'Calling lookup.'},
              {
                'functionCall': {
                  'id': 'call_1',
                  'name': 'lookup',
                  'args': {'query': 'dart'},
                },
              },
            ],
            usage: {
              'promptTokenCount': 10,
              'candidatesTokenCount': 5,
              'totalTokenCount': 15,
            },
          ),
        ),
      ]);
      final client = GeminiChatClient(
        _geminiClient(httpClient),
        modelId: 'gemini-default',
      );

      final response = await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'Hello')],
      );

      expect(response.responseId, 'resp_1');
      expect(response.modelId, 'gemini-test');
      expect(response.finishReason, ChatFinishReason.toolCalls);
      expect(response.usage!.inputTokenCount, 10);
      expect(response.usage!.outputTokenCount, 5);
      expect(response.usage!.totalTokenCount, 15);
      expect(response.rawRepresentation, isA<Map<String, Object?>>());

      final contents = response.messages.single.contents;
      expect((contents[0] as TextContent).text, 'Calling lookup.');
      final call = contents[1] as FunctionCallContent;
      expect(call.callId, 'call_1');
      expect(call.name, 'lookup');
      expect(call.arguments, {'query': 'dart'});
    });

    test('maps streaming text, tool calls, and final usage update', () async {
      final httpClient = _FakeHttpClient([
        _sseResponse([
          _sse({
            'responseId': 'resp_1',
            'modelVersion': 'gemini-test',
            'candidates': [
              {
                'content': {
                  'role': 'model',
                  'parts': [
                    {'text': 'Hel'},
                  ],
                },
              },
            ],
          }),
          _sse({
            'responseId': 'resp_1',
            'modelVersion': 'gemini-test',
            'candidates': [
              {
                'content': {
                  'role': 'model',
                  'parts': [
                    {'text': 'lo'},
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
            'usageMetadata': {
              'promptTokenCount': 4,
              'candidatesTokenCount': 2,
              'totalTokenCount': 6,
            },
          }),
        ]),
      ]);
      final client = GeminiChatClient(
        _geminiClient(httpClient),
        modelId: 'gemini-default',
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
      expect(
        httpClient.requests.single.url.path,
        contains('streamGenerateContent'),
      );
      expect(httpClient.requests.single.url.queryParameters['alt'], 'sse');
    });

    test('sends function call results back as function responses', () async {
      final httpClient = _FakeHttpClient([
        _jsonResponse(_responseJson(text: 'ok')),
      ]);
      final client = GeminiChatClient(
        _geminiClient(httpClient),
        modelId: 'gemini-default',
      );

      await client.getResponse(
        messages: [
          ChatMessage(
            role: ChatRole.tool,
            contents: [
              FunctionResultContent(
                callId: 'lookup',
                name: 'lookup',
                result: {'value': 42},
              ),
            ],
          ),
        ],
      );

      expect(httpClient.requests.single.jsonBody['contents'], [
        {
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': 'lookup',
                'response': {'value': 42},
              },
            },
          ],
        },
      ]);
    });

    test('GeminiClient.asAIAgent applies settings and factory', () {
      final geminiClient = _geminiClient(_FakeHttpClient([]));
      var factoryCalled = false;

      final agent = geminiClient.asAIAgent(
        modelId: 'gemini-default',
        instructions: 'Instructions',
        name: 'GeminiAgent',
        description: 'Gemini-backed agent',
        tools: [_TestFunction(name: 'lookup')],
        clientFactory: (innerClient) {
          factoryCalled = true;
          expect(innerClient, isA<GeminiChatClient>());
          return innerClient;
        },
      );

      expect(factoryCalled, isTrue);
      expect(agent.name, 'GeminiAgent');
      expect(agent.description, 'Gemini-backed agent');
      expect(agent.instructions, 'Instructions');
      expect(agent.chatOptions!.tools, hasLength(1));
    });
  });
}

GeminiClient _geminiClient(http.Client httpClient) {
  return GeminiClient(
    apiKey: 'test-key',
    baseUrl: Uri.parse('https://gemini.test/v1beta'),
    httpClient: httpClient,
  );
}

Map<String, Object?> _responseJson({
  String text = 'ok',
  String finishReason = 'STOP',
  List<Map<String, Object?>>? parts,
  Map<String, Object?> usage = const {
    'promptTokenCount': 1,
    'candidatesTokenCount': 1,
    'totalTokenCount': 2,
  },
}) {
  return {
    'responseId': 'resp_1',
    'modelVersion': 'gemini-test',
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts':
              parts ??
              [
                {'text': text},
              ],
        },
        'finishReason': finishReason,
      },
    ],
    'usageMetadata': usage,
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

String _sse(Map<String, Object?> data) => 'data: ${jsonEncode(data)}\n\n';

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
