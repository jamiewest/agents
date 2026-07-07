// ignore_for_file: non_constant_identifier_names

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedInstant = DateTime.parse('2026-06-11T14:14:00-07:00');

  group('TemporalContextProvider', () {
    test('injects date-only transient temporal instructions', () async {
      final provider = TemporalContextProvider(
        clock: Clock.fixed(fixedInstant),
        timeZoneId: 'America/Los_Angeles',
      );

      final result = await provider.invoking(
        _createInvokingContext(instructions: 'Existing instructions.'),
      );

      expect(result.instructions, startsWith('Existing instructions.\n'));
      expect(result.instructions, contains('Thursday, June 11, 2026'));
      expect(result.instructions, contains('2026-06-11'));
      expect(result.instructions, contains('America/Los_Angeles'));
      expect(result.instructions, contains('today, tomorrow, yesterday'));
      expect(result.instructions, contains('get_current_time'));
      expect(result.instructions, isNot(contains('PM')));
      expect(result.instructions, isNot(contains('14:14')));
      expect(result.messages, isNull);
    });

    test(
      'calls the injected clock once and regenerates each invocation',
      () async {
        final instants = [
          DateTime.parse('2026-06-11T23:59:00-07:00'),
          DateTime.parse('2026-06-12T00:01:00-07:00'),
        ];
        var callCount = 0;
        final clock = Clock(() => instants[callCount++]);
        final provider = TemporalContextProvider(
          clock: clock,
          timeZoneId: 'America/Los_Angeles',
        );

        final first = await provider.invoking(_createInvokingContext());
        final second = await provider.invoking(_createInvokingContext());

        expect(callCount, 2);
        expect(first.instructions, contains('June 11, 2026'));
        expect(second.instructions, contains('June 12, 2026'));
      },
    );

    test('converts the instant to another IANA time zone', () async {
      final provider = TemporalContextProvider(
        clock: Clock.fixed(fixedInstant),
        timeZoneId: 'Asia/Tokyo',
      );

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, contains('Friday, June 12, 2026'));
      expect(result.instructions, contains('2026-06-12'));
    });

    test('detects and caches the device zone when none is given', () async {
      var resolverCalls = 0;
      final provider = TemporalContextProvider(
        clock: Clock.fixed(fixedInstant),
        resolveLocalTimeZone: () async {
          resolverCalls++;
          return 'Asia/Tokyo';
        },
      );

      final first = await provider.invoking(_createInvokingContext());
      final second = await provider.invoking(_createInvokingContext());

      expect(resolverCalls, 1);
      expect(first.instructions, contains('Friday, June 12, 2026'));
      expect(second.instructions, contains('Asia/Tokyo'));
    });

    test('falls back when device-zone detection fails', () async {
      final provider = TemporalContextProvider(
        clock: Clock.fixed(fixedInstant),
        fallbackTimeZoneId: 'Asia/Tokyo',
        resolveLocalTimeZone: () async => throw StateError('no zone'),
      );

      final result = await provider.invoking(_createInvokingContext());

      expect(result.instructions, contains('Friday, June 12, 2026'));
      expect(result.instructions, contains('Asia/Tokyo'));
    });

    test('rejects an unknown IANA time zone', () async {
      final provider = TemporalContextProvider(
        clock: Clock.fixed(fixedInstant),
        timeZoneId: 'Not/A_Zone',
      );

      await expectLater(
        provider.invoking(_createInvokingContext()),
        throwsArgumentError,
      );
    });
  });

  group('get_current_time', () {
    test('uses the clock time zone and returns structured output', () async {
      final tool = createCurrentTimeTool(
        clock: Clock.fixed(fixedInstant),
        timeZoneId: 'America/Los_Angeles',
      );

      final result = await tool.invoke(AIFunctionArguments());

      expect(tool.name, 'get_current_time');
      expect(result, {
        'localDateTime': 'Thursday, June 11, 2026, 2:14 PM',
        'isoTimestamp': '2026-06-11T14:14:00-07:00',
        'timeZoneId': 'America/Los_Angeles',
      });
    });

    test('accepts another IANA time zone', () async {
      final tool = createCurrentTimeTool(
        clock: Clock.fixed(fixedInstant),
        timeZoneId: 'America/Los_Angeles',
      );

      final result =
          await tool.invoke(AIFunctionArguments({'timeZoneId': 'Asia/Tokyo'}))
              as Map<String, Object?>;

      expect(result['localDateTime'], 'Friday, June 12, 2026, 6:14 AM');
      expect(result['isoTimestamp'], '2026-06-12T06:14:00+09:00');
      expect(result['timeZoneId'], 'Asia/Tokyo');
    });

    test('rejects an unknown IANA time zone', () async {
      final tool = createCurrentTimeTool(
        clock: Clock.fixed(fixedInstant),
        timeZoneId: 'America/Los_Angeles',
      );

      await expectLater(
        tool.invoke(AIFunctionArguments({'timeZoneId': 'Not/A_Zone'})),
        throwsArgumentError,
      );
    });
  });

  group('registration', () {
    test('registers the default clock, provider, alias, and tool', () {
      final services = ServiceCollection()..addTemporalContextProvider();
      final serviceProvider = services.buildServiceProvider();

      final clock = serviceProvider.getRequiredService<Clock>();
      final provider = serviceProvider
          .getRequiredService<TemporalContextProvider>();
      final providers = serviceProvider.getServices<AIContextProvider>();
      final tools = serviceProvider.getServices<AITool>();

      expect(clock, isA<Clock>());
      expect(provider.clock, same(clock));
      expect(provider.timeZoneId, isNull);
      expect(provider.fallbackTimeZoneId, 'America/Los_Angeles');
      expect(providers, contains(same(provider)));
      expect(tools.single.name, 'get_current_time');
    });

    test('preserves a clock registered by the caller', () {
      final clock = Clock.fixed(fixedInstant);
      final services = ServiceCollection()
        ..addSingletonInstance<Clock>(clock)
        ..addTemporalContextProvider(
          timeZoneId: 'Asia/Tokyo',
          includeCurrentTimeTool: false,
        );
      final serviceProvider = services.buildServiceProvider();

      expect(serviceProvider.getRequiredService<Clock>(), same(clock));
      expect(
        serviceProvider.getRequiredService<TemporalContextProvider>().clock,
        same(clock),
      );
      expect(
        serviceProvider
            .getRequiredService<TemporalContextProvider>()
            .timeZoneId,
        'Asia/Tokyo',
      );
      expect(serviceProvider.getServices<AITool>(), isEmpty);
    });

    test(
      'options helper preserves existing providers, tools, and settings',
      () {
        final existingProvider = TemporalContextProvider(
          clock: Clock.fixed(fixedInstant),
          timeZoneId: 'Asia/Tokyo',
        );
        final existingTool = AIFunctionFactory.create(
          name: 'existing_tool',
          callback: (_, {cancellationToken}) async => null,
        );
        final options = ChatClientAgentOptions()
          ..chatOptions = ChatOptions(temperature: 0.25, tools: [existingTool])
          ..aiContextProviders = [existingProvider];

        final returned = options.addTemporalContextProvider(
          clock: Clock.fixed(fixedInstant),
          timeZoneId: 'America/Los_Angeles',
        );

        expect(returned, same(options));
        expect(options.aiContextProviders, hasLength(2));
        expect(options.aiContextProviders!.first, same(existingProvider));
        expect(options.chatOptions!.temperature, 0.25);
        expect(options.chatOptions!.tools!.first, same(existingTool));
        expect(options.chatOptions!.tools!.last.name, 'get_current_time');
      },
    );
  });

  test(
    'temporal context reaches requests but is not persisted in history',
    () async {
      final capturedInstructions = <String?>[];
      final client = _CapturingChatClient(capturedInstructions);
      final history = InMemoryChatHistoryProvider();
      final options = ChatClientAgentOptions()
        ..useProvidedChatClientAsIs = true
        ..chatHistoryProvider = history
        ..addTemporalContextProvider(
          clock: Clock.fixed(fixedInstant),
          timeZoneId: 'America/Los_Angeles',
          includeCurrentTimeTool: false,
        );
      final agent = ChatClientAgent(client, options: options);
      final session = await agent.createSession();

      await agent.run(session, null, message: 'What day is tomorrow?');
      await agent.run(session, null, message: 'And the day after that?');

      expect(capturedInstructions, hasLength(2));
      expect(capturedInstructions, everyElement(contains('Temporal context:')));
      final storedMessages = history.getMessages(session);
      expect(storedMessages.map((message) => message.text), [
        'What day is tomorrow?',
        'response',
        'And the day after that?',
        'response',
      ]);
      expect(
        storedMessages.any(
          (message) => message.text.contains('Temporal context'),
        ),
        isFalse,
      );
    },
  );
}

InvokingContext _createInvokingContext({String? instructions}) {
  return InvokingContext(
    _TestAgent(),
    null,
    null,
    AIContext()..instructions = instructions,
  );
}

final class _CapturingChatClient implements ChatClient {
  _CapturingChatClient(this.capturedInstructions);

  final List<String?> capturedInstructions;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    capturedInstructions.add(options?.instructions);
    return ChatResponse.fromMessage(
      ChatMessage.fromText(ChatRole.assistant, 'response'),
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

final class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }
}
