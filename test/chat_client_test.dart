import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/agent_run_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import 'package:agents/src/abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_agent.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_agent_options.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_agent_run_options.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_agent_session.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_builder_extensions.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/chat_client_extensions.dart';
import 'package:agents/src/ai/microsoft_agents_ai/chat_client/per_service_call_chat_history_persisting_chat_client.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('ChatClientAgentRunOptions', () {
    test('clone clones chat options and preserves factory', () {
      final chatOptions = ChatOptions(
        instructions: 'Base',
        tools: [_TestTool('tool')],
      );
      ChatClient factory(ChatClient client) => client;
      final options = ChatClientAgentRunOptions(chatOptions: chatOptions)
        ..chatClientFactory = factory;

      final clone = options.clone() as ChatClientAgentRunOptions;

      expect(clone, isNot(same(options)));
      expect(clone.chatOptions, isNot(same(chatOptions)));
      expect(clone.chatOptions!.instructions, 'Base');
      expect(clone.chatOptions!.tools, hasLength(1));
      expect(clone.chatClientFactory, same(factory));
    });
  });

  group('ChatClient builder extensions', () {
    test('buildAIAgent with basic parameters creates agent', () {
      final client = _ScriptedChatClient();
      final tools = [_TestTool('tool')];

      final agent = ChatClientBuilder(client).buildAIAgent(
        instructions: 'Instructions',
        name: 'TestAgent',
        description: 'Description',
        tools: tools,
      );

      expect(agent.name, 'TestAgent');
      expect(agent.description, 'Description');
      expect(agent.instructions, 'Instructions');
      expect(agent.chatOptions!.tools, tools);
    });

    test('buildAIAgent with options creates agent with options', () {
      final options = ChatClientAgentOptions()
        ..name = 'OptionAgent'
        ..description = 'Option description'
        ..chatOptions = ChatOptions(instructions: 'Option instructions')
        ..useProvidedChatClientAsIs = true;

      final agent = ChatClientBuilder(
        _ScriptedChatClient(),
      ).buildAIAgent(options: options);

      expect(agent.name, 'OptionAgent');
      expect(agent.description, 'Option description');
      expect(agent.instructions, 'Option instructions');
    });

    test('usePerServiceCallChatHistoryPersistence adds decorator', () {
      final client = ChatClientBuilder(
        _ScriptedChatClient(),
      ).usePerServiceCallChatHistoryPersistence().build();

      expect(client, isA<PerServiceCallChatHistoryPersistingChatClient>());
    });
  });

  group('ChatClient extensions', () {
    test('asAIAgent creates agent from chat client', () {
      final agent = _ScriptedChatClient().asAIAgent(
        instructions: 'Instructions',
        name: 'Agent',
      );

      expect(agent, isA<ChatClientAgent>());
      expect(agent.name, 'Agent');
      expect(agent.instructions, 'Instructions');
    });
  });

  group('ChatClientAgent', () {
    test(
      'sets current run context during non-streaming run and restores it',
      () async {
        AgentRunContext? capturedContext;
        final previousContext = AgentRunContext(
          ChatClientAgent(
            _ScriptedChatClient(),
            options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
          ),
          ChatClientAgentSession(),
          const [],
          null,
        );
        AIAgent.currentRunContext = previousContext;

        final client = _ScriptedChatClient()
          ..onGetResponse = (messages, options, cancellationToken) {
            capturedContext = AIAgent.currentRunContext;
            return ChatResponse.fromMessage(_assistantText('response'));
          };
        final agent = ChatClientAgent(
          client,
          options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
        );
        final session = ChatClientAgentSession();

        await agent.runCore([_userText('Hello')], session: session);

        expect(capturedContext, isNotNull);
        expect(capturedContext!.agent, same(agent));
        expect(capturedContext!.session, same(session));
        expect(AIAgent.currentRunContext, same(previousContext));
        AIAgent.currentRunContext = null;
      },
    );

    test(
      'sets current run context during streaming run and restores it',
      () async {
        AgentRunContext? capturedContext;
        final client = _ScriptedChatClient()
          ..onGetStreamingResponse =
              (messages, options, cancellationToken) async* {
                capturedContext = AIAgent.currentRunContext;
                yield ChatResponseUpdate.fromText(
                  ChatRole.assistant,
                  'response',
                );
              };
        final agent = ChatClientAgent(
          client,
          options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
        );
        final session = ChatClientAgentSession();

        final updates = await agent.runCoreStreaming([
          _userText('Hello'),
        ], session: session).toList();

        expect(updates.single.text, 'response');
        expect(capturedContext, isNotNull);
        expect(capturedContext!.agent, same(agent));
        expect(capturedContext!.session, same(session));
        expect(AIAgent.currentRunContext, isNull);
      },
    );

    test('applies session conversation id to created chat options', () async {
      ChatOptions? capturedOptions;
      final client = _ScriptedChatClient()
        ..onGetResponse = (messages, options, cancellationToken) {
          capturedOptions = options;
          return ChatResponse(
            messages: [_assistantText('response')],
            conversationId: options?.conversationId,
          );
        };
      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      final session = ChatClientAgentSession(conversationId: 'conversation-1');

      await agent.runCore([_userText('Hello')], session: session);

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.conversationId, 'conversation-1');
    });

    test(
      'materializes AI context provider tools and instructions into options',
      () async {
        ChatOptions? capturedOptions;
        final providedTool = _TestTool('provided');
        final client = _ScriptedChatClient()
          ..onGetResponse = (messages, options, cancellationToken) {
            capturedOptions = options;
            return ChatResponse.fromMessage(_assistantText('response'));
          };
        final agentOptions = ChatClientAgentOptions()
          ..useProvidedChatClientAsIs = true
          ..aiContextProviders = [
            _TestAIContextProvider(
              instructions: 'Extra instructions',
              tools: [providedTool],
            ),
          ];
        final agent = ChatClientAgent(client, options: agentOptions);

        await agent.runCore([
          _userText('Hello'),
        ], session: ChatClientAgentSession());

        expect(capturedOptions, isNotNull);
        expect(capturedOptions!.instructions, 'Extra instructions');
        expect(capturedOptions!.tools, [providedTool]);
      },
    );

    test('run options chat client factory replaces client', () async {
      final originalClient = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) {
          throw StateError('original should not be called');
        };
      final transformedClient = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) {
          return ChatResponse.fromMessage(_assistantText('transformed'));
        };
      var factoryCalls = 0;
      final agent = ChatClientAgent(
        originalClient,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      final options = ChatClientAgentRunOptions()
        ..chatClientFactory = (client) {
          factoryCalls++;
          expect(client, same(originalClient));
          return transformedClient;
        };

      final response = await agent.runCore(
        [_userText('Hello')],
        session: ChatClientAgentSession(),
        options: options,
      );

      expect(response.text, 'transformed');
      expect(factoryCalls, 1);
    });
  });
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

class _TestAIContextProvider extends AIContextProvider {
  _TestAIContextProvider({this.instructions, this.tools});

  final String? instructions;
  final Iterable<AITool>? tools;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    return AIContext()
      ..instructions = instructions
      ..tools = tools;
  }
}

class _TestTool extends AITool {
  _TestTool(String name) : super(name: name);
}

ChatMessage _userText(String text) => ChatMessage.fromText(ChatRole.user, text);

ChatMessage _assistantText(String text) =>
    ChatMessage.fromText(ChatRole.assistant, text);
