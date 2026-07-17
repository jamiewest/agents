// Copyright (c) Microsoft. All rights reserved.
//
// Ported in spirit from OpenAIMapOptionsTests.cs and
// OpenAIResponseRequestInfoBuilderTests.cs.

import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/hosting/open_ai/chat_completions/converters/chat_client_agent_run_options_converter.dart';
import 'package:agents/src/hosting/open_ai/chat_completions/models/create_chat_completion.dart';
import 'package:agents/src/hosting/open_ai/open_ai_chat_completions_map_options.dart';
import 'package:agents/src/hosting/open_ai/open_ai_response_request_info.dart';
import 'package:agents/src/hosting/open_ai/open_ai_responses_map_options.dart';
import 'package:agents/src/hosting/open_ai/responses/ai_agent_response_executor.dart';
import 'package:agents/src/hosting/open_ai/responses/hosted_agent_response_executor.dart';
import 'package:agents/src/hosting/open_ai/responses/models/create_response.dart';
import 'package:agents/src/hosting/open_ai/responses/open_ai_response_request_info_builder.dart';
import 'package:agents/src/hosting/open_ai/responses/response_error_codes.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAIResponsesMapOptions.rejectRequestSettings', () {
    test('returns null for a request with no mappable settings', () {
      final options = OpenAIResponsesMapOptions.rejectRequestSettings(
        OpenAIResponseRequestInfo()..model = 'gpt-4o',
      );

      expect(options, isNull);
    });

    test('throws listing every unsupported setting', () {
      final info = OpenAIResponseRequestInfo()
        ..temperature = 0.5
        ..instructions = 'be terse'
        ..toolChoice = ChatToolMode.auto;

      expect(
        () => OpenAIResponsesMapOptions.rejectRequestSettings(info),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('temperature'),
              contains('instructions'),
              contains('tool_choice'),
            ),
          ),
        ),
      );
    });
  });

  group('CreateResponse.toRequestInfo', () {
    test('maps sampling, instructions, tools, and tool_choice', () {
      final request = CreateResponse.fromJson({
        'model': 'gpt-4o',
        'input': 'hi',
        'temperature': 0.25,
        'top_p': 0.9,
        'max_output_tokens': 16,
        'instructions': 'be terse',
        'tools': [
          {'type': 'function', 'name': 'lookup'},
        ],
        'tool_choice': {'type': 'function', 'name': 'lookup'},
      });

      final info = request.toRequestInfo();

      expect(info.model, 'gpt-4o');
      expect(info.temperature, 0.25);
      expect(info.topP, 0.9);
      expect(info.maxOutputTokens, 16);
      expect(info.instructions, 'be terse');
      expect(info.tools, hasLength(1));
      expect(info.toolChoice, isA<RequiredChatToolMode>());
    });

    test('maps string tool_choice modes and leaves unknowns null', () {
      OpenAIResponseRequestInfo infoFor(Object? toolChoice) =>
          CreateResponse.fromJson({
            'input': 'hi',
            'tool_choice': toolChoice,
          }).toRequestInfo();

      expect(infoFor('none'), isA<OpenAIResponseRequestInfo>());
      expect(infoFor('none').toolChoice, ChatToolMode.none);
      expect(infoFor('auto').toolChoice, ChatToolMode.auto);
      expect(infoFor('required').toolChoice, ChatToolMode.requireAny);
      expect(infoFor('custom').toolChoice, isNull);
      expect(infoFor({'type': 'mcp'}).toolChoice, isNull);
    });
  });

  group('AIAgentResponseExecutor validation', () {
    test(
      'rejects request settings with unsupported_parameter by default',
      () async {
        final executor = AIAgentResponseExecutor(_EchoAgent());
        final request = CreateResponse.fromJson({
          'input': 'hi',
          'temperature': 0.1,
        });

        final error = await executor.validateRequest(request);

        expect(error, isNotNull);
        expect(error!.code, 'unsupported_parameter');
        expect(error.message, contains('temperature'));
      },
    );

    test('honors a custom runOptionsFactory', () async {
      OpenAIResponseRequestInfo? seen;
      final executor = AIAgentResponseExecutor(
        _EchoAgent(),
        mapOptions: OpenAIResponsesMapOptions()
          ..runOptionsFactory = (info) {
            seen = info;
            return AgentRunOptions();
          },
      );
      final request = CreateResponse.fromJson({
        'input': 'hi',
        'temperature': 0.1,
      });

      final error = await executor.validateRequest(request);

      expect(error, isNull);
      expect(seen?.temperature, 0.1);
    });
  });

  group('HostedAgentResponseExecutor', () {
    HostedAgentResponseExecutor newExecutor({AIAgent? agent}) =>
        HostedAgentResponseExecutor(
          (name) => name == 'echo' ? (agent ?? _EchoAgent()) : null,
        );

    test('requires agent.name or metadata entity_id', () async {
      final error = await newExecutor().validateRequest(
        CreateResponse.fromJson({'input': 'hi'}),
      );

      expect(error, isNotNull);
      expect(error!.code, 'missing_required_parameter');
    });

    test('reports unresolvable agents as agent_not_found', () async {
      final error = await newExecutor().validateRequest(
        CreateResponse.fromJson({
          'input': 'hi',
          'agent': {'type': 'agent_reference', 'name': 'nope'},
        }),
      );

      expect(error, isNotNull);
      expect(error!.code, 'agent_not_found');
    });

    test(
      'resolves by agent.name and falls back to metadata entity_id',
      () async {
        final byAgent = await newExecutor().validateRequest(
          CreateResponse.fromJson({
            'input': 'hi',
            'agent': {'type': 'agent_reference', 'name': 'echo'},
          }),
        );
        final byMetadata = await newExecutor().validateRequest(
          CreateResponse.fromJson({
            'input': 'hi',
            'metadata': {'entity_id': 'echo'},
          }),
        );

        expect(byAgent, isNull);
        expect(byMetadata, isNull);
      },
    );

    test('surfaces unsupported request settings during validation', () async {
      final error = await newExecutor().validateRequest(
        CreateResponse.fromJson({
          'input': 'hi',
          'temperature': 0.1,
          'agent': {'type': 'agent_reference', 'name': 'echo'},
        }),
      );

      expect(error, isNotNull);
      expect(error!.code, 'unsupported_parameter');
    });
  });

  group('OpenAIChatCompletionsMapOptions.rejectRequestSettings', () {
    test('allows the required model field', () {
      final request = CreateChatCompletion.fromJson({
        'model': 'gpt-4o',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });

      final options = OpenAIChatCompletionsMapOptions.rejectRequestSettings(
        request.toRequestInfo(),
      );

      expect(options, isNull);
    });

    test('throws listing every unsupported setting', () {
      final request = CreateChatCompletion.fromJson({
        'model': 'gpt-4o',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'temperature': 0.5,
        'seed': 7,
        'stop': ['END'],
      });

      expect(
        () => OpenAIChatCompletionsMapOptions.rejectRequestSettings(
          request.toRequestInfo(),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(contains('temperature'), contains('seed'), contains('stop')),
          ),
        ),
      );
    });
  });

  group('ResponseErrorCodes.mapValidationError', () {
    test('maps conversation_not_found to 404 with no wire code', () {
      expect(
        ResponseErrorCodes.mapValidationError(
          ResponseErrorCodes.conversationNotFound,
        ),
        (404, null),
      );
    });

    test('maps other codes to 400 preserving the code', () {
      expect(ResponseErrorCodes.mapValidationError('unsupported_parameter'), (
        400,
        'unsupported_parameter',
      ));
    });
  });
}

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
  }) async =>
      AgentResponse(message: ChatMessage.fromText(ChatRole.assistant, 'echo'));

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    yield AgentResponseUpdate(role: ChatRole.assistant, content: 'echo');
  }
}

class _EchoSession extends AgentSession {
  _EchoSession() : super(AgentSessionStateBag(null));
}
