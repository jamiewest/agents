import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/message_ai_context_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/agent_extensions.dart';
import 'package:agents/src/ai/microsoft_agents_ai/logging_agent.dart';
import 'package:agents/src/ai/microsoft_agents_ai/logging_agent_builder_extensions.dart';
import 'package:agents/src/ai/microsoft_agents_ai/open_telemetry_agent.dart';
import 'package:agents/src/ai/microsoft_agents_ai/open_telemetry_agent_builder_extensions.dart';
import 'package:agents/src/ai/microsoft_agents_ai/text_search_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/text_search_provider_options.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AIAgent extensions', () {
    test('asBuilder composes wrappers around the current agent', () {
      final inner = _TestAgent();

      final built = inner
          .asBuilder()
          .useLogging(loggerFactory: LoggerFactory())
          .build();

      expect(built, isA<LoggingAgent>());
    });

    test('useLogging is no-op for null logger factory', () {
      final inner = _TestAgent();

      final built = inner.asBuilder().useLogging().build();

      expect(identical(built, inner), isTrue);
    });

    test('useOpenTelemetry wraps and delegates to inner agent', () async {
      final inner = _TestAgent(responseText: 'otel-result');
      final built = inner.asBuilder().useOpenTelemetry().build();

      final response = await built.run(
        null,
        null,
        cancellationToken: CancellationToken.none,
        message: 'hello',
      );

      expect(built, isA<OpenTelemetryAgent>());
      expect(response.text, 'otel-result');
      expect(inner.lastMessages.single.text, 'hello');
    });

    test(
      'asAIFunction sanitizes name and invokes agent with session',
      () async {
        final inner = _TestAgent(
          nameValue: 'Research Agent!',
          descriptionValue: 'Finds answers.',
          responseText: 'answer',
        );
        final session = _TestSession();
        final function = inner.asAIFunction(session: session);

        final result = await function.invoke(
          AIFunctionArguments({'query': 'question'}),
        );

        expect(function.name, 'Research_Agent');
        expect(function.description, 'Finds answers.');
        expect(result, 'answer');
        expect(identical(inner.lastSession, session), isTrue);
        expect(inner.lastMessages.single.text, 'question');
      },
    );
  });

  group('TextSearchProvider', () {
    test('before invoke injects formatted search results', () async {
      final inputs = <String>[];
      final provider = TextSearchProvider((input, _) async {
        inputs.add(input);
        return [
          TextSearchResult(
            sourceName: 'guide',
            sourceLink: 'https://example.test/guide',
            text: 'retrieved text',
          ),
        ];
      });

      final context = await provider.provideAIContext(
        InvokingContext(
          _TestAgent(),
          null,
          AIContext()
            ..messages = [ChatMessage.fromText(ChatRole.user, 'what is this?')],
        ),
      );

      expect(inputs, ['what is this?']);
      expect(context.messages!.single.text, contains('SourceDocName: guide'));
      expect(context.messages!.single.text, contains('retrieved text'));
    });

    test('on demand mode exposes search tool', () async {
      final provider = TextSearchProvider(
        (input, _) async => [TextSearchResult(text: 'result for $input')],
        options: TextSearchProviderOptions()
          ..searchTime = TextSearchBehavior.onDemandFunctionCalling
          ..functionToolName = 'lookup',
      );

      final context = await provider.provideAIContext(
        InvokingContext(_TestAgent(), null, AIContext()),
      );

      expect(context.messages, isNull);
      expect(context.tools!.single, isA<AIFunction>());
      final tool = context.tools!.single as AIFunction;
      expect(tool.name, 'lookup');
      expect(
        await tool.invoke(AIFunctionArguments({'userQuestion': 'needle'})),
        contains('result for needle'),
      );
    });

    test(
      'recent messages persist per session and are included in search input',
      () async {
        final inputs = <String>[];
        final session = _TestSession();
        final provider = TextSearchProvider((input, _) async {
          inputs.add(input);
          return [TextSearchResult(text: 'memory result')];
        }, options: TextSearchProviderOptions()..recentMessageMemoryLimit = 2);

        await provider.storeAIContext(
          InvokedContext(
            _TestAgent(),
            session,
            [ChatMessage.fromText(ChatRole.user, 'first')],
            responseMessages: [
              ChatMessage.fromText(ChatRole.assistant, 'assistant ignored'),
            ],
          ),
        );
        await provider.storeAIContext(
          InvokedContext(_TestAgent(), session, [
            ChatMessage.fromText(ChatRole.user, 'second'),
          ]),
        );

        await provider.provideAIContext(
          InvokingContext(
            _TestAgent(),
            session,
            AIContext()
              ..messages = [ChatMessage.fromText(ChatRole.user, 'current')],
          ),
        );

        expect(inputs.single, 'first\nsecond\ncurrent');
      },
    );

    test('custom formatter receives snapshot list', () async {
      late List<TextSearchResult> received;
      final provider = TextSearchProvider(
        (_, _) async => [TextSearchResult(text: 'one')],
        options: TextSearchProviderOptions()
          ..contextFormatter = (results) {
            received = results;
            expect(
              () => results.add(TextSearchResult()),
              throwsUnsupportedError,
            );
            return 'custom ${results.single.text}';
          },
      );

      final context = await provider.provideAIContext(
        InvokingContext(
          _TestAgent(),
          null,
          AIContext()..messages = [ChatMessage.fromText(ChatRole.user, 'q')],
        ),
      );

      expect(received.single.text, 'one');
      expect(context.messages!.single.text, 'custom one');
    });
  });
}

class _TestAgent extends AIAgent {
  _TestAgent({
    this.nameValue = 'test-agent',
    this.descriptionValue = 'Test agent.',
    this.responseText = 'response',
  });

  final String? nameValue;
  final String? descriptionValue;
  final String responseText;

  List<ChatMessage> lastMessages = [];
  AgentSession? lastSession;

  @override
  String? get name => nameValue;

  @override
  String? get description => descriptionValue;

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    serializedState, {
    JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    lastMessages = messages.toList();
    lastSession = session;
    return AgentResponse(
      message: ChatMessage.fromText(ChatRole.assistant, responseText),
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    lastMessages = messages.toList();
    lastSession = session;
    yield AgentResponseUpdate(role: ChatRole.assistant, content: responseText);
  }

  @override
  Future serializeSessionCore(
    AgentSession session, {
    JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}
