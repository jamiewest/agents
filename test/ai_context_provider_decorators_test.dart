import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/message_ai_context_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/ai_agent_builder.dart';
import 'package:agents/src/ai/microsoft_agents_ai/ai_context_provider_decorators/ai_context_provider_chat_client.dart';
import 'package:agents/src/ai/microsoft_agents_ai/ai_context_provider_decorators/ai_context_provider_chat_client_builder_extensions.dart';
import 'package:agents/src/ai/microsoft_agents_ai/ai_context_provider_decorators/message_ai_context_provider_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('MessageAIContextProviderAgent', () {
    test('constructor validates arguments', () {
      final provider = _TestMessageProvider();
      final agent = _ScriptedAgent();

      expect(
        () => MessageAIContextProviderAgent(null, [provider]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => MessageAIContextProviderAgent(agent, null),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => MessageAIContextProviderAgent(agent, []),
        throwsA(isA<RangeError>()),
      );
    });

    test('single provider enriches messages and notifies success', () async {
      final provider = _TestMessageProvider(
        provideMessages: [_systemText('Extra context')],
      );
      final innerAgent = _ScriptedAgent()
        ..onRun = (messages, session, options, cancellationToken) {
          return _agentResponseText('response');
        };
      final agent = MessageAIContextProviderAgent(innerAgent, [provider]);

      await agent.runCore([_userText('Hello')], session: _TestSession());

      final captured = innerAgent.capturedRuns.single;
      expect(captured.map((m) => m.text), ['Hello', 'Extra context']);
      expect(provider.invokedCalled, isTrue);
      expect(provider.lastInvokedContext!.invokeException, isNull);
      expect(
        provider.lastInvokedContext!.responseMessages!.single.text,
        'response',
      );
    });

    test(
      'multiple providers run in sequence with filtered provider input',
      () async {
        Iterable<ChatMessage>? provider2Input;
        final provider1 = _TestMessageProvider(
          provideMessages: [_systemText('From provider 1')],
        );
        final provider2 = _TestMessageProvider(
          provideMessages: [_systemText('From provider 2')],
          onProvide: (messages) => provider2Input = messages,
        );
        final innerAgent = _ScriptedAgent()
          ..onRun = (_, _, _, _) => _agentResponseText('response');
        final agent = MessageAIContextProviderAgent(innerAgent, [
          provider1,
          provider2,
        ]);

        await agent.runCore([_userText('Hello')], session: _TestSession());

        expect(innerAgent.capturedRuns.single.map((m) => m.text), [
          'Hello',
          'From provider 1',
          'From provider 2',
        ]);
        expect(provider2Input!.map((m) => m.text), ['Hello']);
      },
    );

    test('failure notifies provider with exception', () async {
      final provider = _TestMessageProvider();
      final exception = Exception('Agent failed');
      final innerAgent = _ScriptedAgent()
        ..onRun = (_, _, _, _) => throw exception;
      final agent = MessageAIContextProviderAgent(innerAgent, [provider]);

      await expectLater(
        () => agent.runCore([_userText('Hello')], session: _TestSession()),
        throwsA(same(exception)),
      );

      expect(provider.invokedCalled, isTrue);
      expect(provider.lastInvokedContext!.invokeException, same(exception));
    });

    test(
      'streaming enriches messages and accumulates response messages',
      () async {
        final provider = _TestMessageProvider(
          provideMessages: [_systemText('Extra context')],
        );
        final innerAgent = _ScriptedAgent()
          ..onRunStreaming = (_, _, _, _) async* {
            yield AgentResponseUpdate(
              role: ChatRole.assistant,
              content: 'Hello ',
            );
            yield AgentResponseUpdate(
              role: ChatRole.assistant,
              content: 'World',
            );
          };
        final agent = MessageAIContextProviderAgent(innerAgent, [provider]);

        final updates = await agent.runCoreStreaming([
          _userText('Hello'),
        ], session: _TestSession()).toList();

        expect(updates.map((u) => u.text).join(), 'Hello World');
        expect(innerAgent.capturedStreams.single, hasLength(2));
        expect(provider.invokedCalled, isTrue);
        expect(
          provider.lastInvokedContext!.responseMessages!.single.text,
          'Hello World',
        );
      },
    );

    test('builder extension creates working pipeline', () async {
      final provider = _TestMessageProvider(
        provideMessages: [_systemText('Pipeline context')],
      );
      final innerAgent = _ScriptedAgent()
        ..onRun = (_, _, _, _) => _agentResponseText('response');

      final pipeline = AIAgentBuilder(
        innerAgent: innerAgent,
      ).useAIContextProviders([provider]).build();

      await pipeline.runCore([_userText('Hello')], session: _TestSession());

      expect(innerAgent.capturedRuns.single.map((m) => m.text), [
        'Hello',
        'Pipeline context',
      ]);
    });
  });

  group('AIContextProviderChatClient', () {
    test('constructor validates arguments', () {
      final provider = _TestAIContextProvider();
      final client = _ScriptedChatClient();

      expect(
        () => AIContextProviderChatClient(null, [provider]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AIContextProviderChatClient(client, null),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AIContextProviderChatClient(client, []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getResponse requires run context', () async {
      final client = AIContextProviderChatClient(_ScriptedChatClient(), [
        _TestAIContextProvider(),
      ]);

      final previous = AIAgent.currentRunContext;
      AIAgent.currentRunContext = null;
      try {
        await expectLater(
          () => client.getResponse(messages: [_userText('Hello')]),
          throwsStateError,
        );
      } finally {
        AIAgent.currentRunContext = previous;
      }
    });

    test('single provider enriches messages', () async {
      Iterable<ChatMessage>? capturedMessages;
      final innerClient = _ScriptedChatClient()
        ..onGetResponse = (messages, options, cancellationToken) {
          capturedMessages = messages;
          return ChatResponse.fromMessage(_assistantText('response'));
        };
      final provider = _TestAIContextProvider(
        provideMessages: [_systemText('Extra context')],
      );
      final client = AIContextProviderChatClient(innerClient, [provider]);

      await _runWithAgentContext(
        () => client.getResponse(messages: [_userText('Hello')]),
      );

      expect(capturedMessages!.map((m) => m.text), ['Hello', 'Extra context']);
      expect(provider.invokedCalled, isTrue);
      expect(provider.lastInvokedContext!.invokeException, isNull);
    });

    test(
      'providers enrich tools and instructions without mutating options',
      () async {
        final baselineTool = _TestTool('baseline');
        final providedTool = _TestTool('provided');
        final counts = <int>[];
        final innerClient = _ScriptedChatClient()
          ..onGetResponse = (messages, options, cancellationToken) {
            counts.add(options?.tools?.length ?? 0);
            expect(options!.instructions, 'Base\nExtra');
            return ChatResponse.fromMessage(_assistantText('response'));
          };
        final provider = _TestAIContextProvider(
          provideInstructions: 'Extra',
          provideTools: [providedTool],
        );
        final client = AIContextProviderChatClient(innerClient, [provider]);
        final sharedOptions = ChatOptions(
          instructions: 'Base',
          tools: [baselineTool],
        );

        await _runWithAgentContext(
          () => client.getResponse(
            messages: [_userText('Hello')],
            options: sharedOptions,
          ),
        );
        await _runWithAgentContext(
          () => client.getResponse(
            messages: [_userText('Hello')],
            options: sharedOptions,
          ),
        );

        expect(counts, [2, 2]);
        expect(sharedOptions.tools, [baselineTool]);
        expect(sharedOptions.instructions, 'Base');
      },
    );

    test('getResponse failure notifies provider with exception', () async {
      final exception = Exception('Chat failed');
      final innerClient = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) => throw exception;
      final provider = _TestAIContextProvider();
      final client = AIContextProviderChatClient(innerClient, [provider]);

      await expectLater(
        () => _runWithAgentContext(
          () => client.getResponse(messages: [_userText('Hello')]),
        ),
        throwsA(same(exception)),
      );

      expect(provider.invokedCalled, isTrue);
      expect(provider.lastInvokedContext!.invokeException, same(exception));
    });

    test('streaming enriches messages and notifies success', () async {
      Iterable<ChatMessage>? capturedMessages;
      final innerClient = _ScriptedChatClient()
        ..onGetStreamingResponse =
            (messages, options, cancellationToken) async* {
              capturedMessages = messages;
              yield ChatResponseUpdate.fromText(ChatRole.assistant, 'Part1');
              yield ChatResponseUpdate.fromText(ChatRole.assistant, 'Part2');
            };
      final provider = _TestAIContextProvider(
        provideMessages: [_systemText('Extra context')],
      );
      final client = AIContextProviderChatClient(innerClient, [provider]);

      final updates = await _runWithAgentContext(
        () => client
            .getStreamingResponse(messages: [_userText('Hello')])
            .toList(),
      );

      expect(updates.map((u) => u.text).join(), 'Part1Part2');
      expect(capturedMessages!.map((m) => m.text), ['Hello', 'Extra context']);
      expect(provider.invokedCalled, isTrue);
      expect(
        provider.lastInvokedContext!.responseMessages!.single.text,
        'Part1Part2',
      );
    });

    test('streaming failure notifies provider with exception', () async {
      final exception = Exception('Stream failed');
      final innerClient = _ScriptedChatClient()
        ..onGetStreamingResponse = (_, _, _) async* {
          throw exception;
        };
      final provider = _TestAIContextProvider();
      final client = AIContextProviderChatClient(innerClient, [provider]);

      await expectLater(
        () => _runWithAgentContext(
          () => client
              .getStreamingResponse(messages: [_userText('Hello')])
              .toList(),
        ),
        throwsA(same(exception)),
      );

      expect(provider.invokedCalled, isTrue);
      expect(provider.lastInvokedContext!.invokeException, same(exception));
    });

    test('builder extension creates working pipeline', () async {
      Iterable<ChatMessage>? capturedMessages;
      final innerClient = _ScriptedChatClient()
        ..onGetResponse = (messages, options, cancellationToken) {
          capturedMessages = messages;
          return ChatResponse.fromMessage(_assistantText('response'));
        };
      final provider = _TestAIContextProvider(
        provideMessages: [_systemText('Pipeline context')],
      );
      final pipeline = ChatClientBuilder(
        innerClient,
      ).useAIContextProviders([provider]).build();

      await _runWithAgentContext(
        () => pipeline.getResponse(messages: [_userText('Hello')]),
      );

      expect(capturedMessages!.map((m) => m.text), [
        'Hello',
        'Pipeline context',
      ]);
    });
  });
}

class _ScriptedAgent extends AIAgent {
  AgentResponse Function(
    Iterable<ChatMessage> messages,
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  )?
  onRun;

  Stream<AgentResponseUpdate> Function(
    Iterable<ChatMessage> messages,
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  )?
  onRunStreaming;

  final capturedRuns = <List<ChatMessage>>[];
  final capturedStreams = <List<ChatMessage>>[];

  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    capturedRuns.add(List<ChatMessage>.of(messages));
    return onRun?.call(messages, session, options, cancellationToken) ??
        _agentResponseText('response');
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    capturedStreams.add(List<ChatMessage>.of(messages));
    final stream = onRunStreaming?.call(
      messages,
      session,
      options,
      cancellationToken,
    );
    if (stream == null) {
      yield AgentResponseUpdate(role: ChatRole.assistant, content: 'response');
      return;
    }
    yield* stream;
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    // ignore: non_constant_identifier_names
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => null;
}

class _ScriptedChatClient implements ChatClient {
  ChatResponse Function(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  )?
  onGetResponse;

  Stream<ChatResponseUpdate> Function(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  )?
  onGetStreamingResponse;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    return onGetResponse?.call(messages, options, cancellationToken) ??
        ChatResponse.fromMessage(_assistantText('response'));
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final stream = onGetStreamingResponse?.call(
      messages,
      options,
      cancellationToken,
    );
    if (stream == null) {
      yield ChatResponseUpdate.fromText(ChatRole.assistant, 'response');
      return;
    }
    yield* stream;
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}
}

class _TestMessageProvider extends MessageAIContextProvider {
  _TestMessageProvider({Iterable<ChatMessage>? provideMessages, this.onProvide})
    : _provideMessages = provideMessages ?? const <ChatMessage>[];

  final Iterable<ChatMessage> _provideMessages;
  final void Function(Iterable<ChatMessage> messages)? onProvide;

  bool invokedCalled = false;
  InvokedContext? lastInvokedContext;

  @override
  Future<Iterable<ChatMessage>> provideMessages(
    MessageInvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    onProvide?.call(context.requestMessages);
    return _provideMessages;
  }

  @override
  Future<void> invokedCore(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    invokedCalled = true;
    lastInvokedContext = context;
  }
}

class _TestAIContextProvider extends AIContextProvider {
  _TestAIContextProvider({
    Iterable<ChatMessage>? provideMessages,
    String? provideInstructions,
    Iterable<AITool>? provideTools,
  }) : _provideMessages = provideMessages,
       _provideInstructions = provideInstructions,
       _provideTools = provideTools;

  final Iterable<ChatMessage>? _provideMessages;
  final String? _provideInstructions;
  final Iterable<AITool>? _provideTools;

  bool invokedCalled = false;
  InvokedContext? lastInvokedContext;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    return AIContext()
      ..messages = _provideMessages
      ..instructions = _provideInstructions
      ..tools = _provideTools;
  }

  @override
  Future<void> invokedCore(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    invokedCalled = true;
    lastInvokedContext = context;
  }
}

class _TestTool extends AITool {
  _TestTool(String name) : super(name: name);
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

Future<T> _runWithAgentContext<T>(Future<T> Function() action) async {
  final previous = AIAgent.currentRunContext;
  AIAgent.currentRunContext = AgentRunContext(
    _ScriptedAgent(),
    _TestSession(),
    [_userText('Hello')],
    null,
  );
  try {
    return await action();
  } finally {
    AIAgent.currentRunContext = previous;
  }
}

ChatMessage _userText(String text) => ChatMessage.fromText(ChatRole.user, text);

ChatMessage _systemText(String text) =>
    ChatMessage.fromText(ChatRole.system, text);

ChatMessage _assistantText(String text) =>
    ChatMessage.fromText(ChatRole.assistant, text);

AgentResponse _agentResponseText(String text) {
  return AgentResponse(message: _assistantText(text));
}
