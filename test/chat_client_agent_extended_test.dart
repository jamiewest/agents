// ignore_for_file: non_constant_identifier_names
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/ai_agent_metadata.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent_options.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent_run_options.dart';
import 'package:agents/src/ai/chat_client/chat_client_agent_session.dart';
import 'package:agents/src/ai/chat_client/chat_client_builder_extensions.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => AIAgent.currentRunContext = null);

  // ── getService ─────────────────────────────────────────────────────────────

  group('ChatClientAgent.getService', () {
    test(
      'requestingAIAgentMetadataReturnsIt',
      () {
        final agent = _makeAgent();
        final metadata = agent.getService(AIAgentMetadata);
        expect(metadata, isA<AIAgentMetadata>());
      },
    );

    test(
      'requestingAIAgentMetadataReturnsConsistentInstance',
      () {
        final agent = _makeAgent();
        final first = agent.getService(AIAgentMetadata);
        final second = agent.getService(AIAgentMetadata);
        expect(identical(first, second), isTrue);
      },
    );

    test('requestingChatClientReturnsChatClient', () {
      final client = _ScriptedChatClient();
      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      expect(agent.getService(ChatClient), isNotNull);
    });

    test('requestingChatClientAgentReturnsSelf', () {
      final agent = _makeAgent();
      expect(agent.getService(ChatClientAgent), same(agent));
    });

    test('requestingAIAgentReturnsSelf', () {
      final agent = _makeAgent();
      expect(agent.getService(AIAgent), same(agent));
    });

    test('requestingUnknownTypeReturnsNull', () {
      final agent = _makeAgent();
      expect(agent.getService(String), isNull);
    });

    test(
      'requestingAIAgentMetadataIncludesProviderNameFromChatClientMetadata',
      () {
        final client = _ScriptedChatClient(
          metadata: ChatClientMetadata(providerName: 'openai'),
        );
        final agent = ChatClientAgent(
          client,
          options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
        );
        final metadata = agent.getService(AIAgentMetadata) as AIAgentMetadata;
        expect(metadata.providerName, 'openai');
      },
    );
  });

  // ── Session serialization ──────────────────────────────────────────────────

  group('ChatClientAgent session serialization', () {
    test('serializeSessionCore serializes ChatClientAgentSession to JSON', () async {
      final agent = _makeAgent();
      final session = ChatClientAgentSession(conversationId: 'conv-42');
      final serialized = await agent.serializeSession(session);
      expect(serialized, isA<String>());
      expect(serialized as String, contains('conv-42'));
    });

    test('deserializeSessionCore restores conversation id', () async {
      final agent = _makeAgent();
      final session = ChatClientAgentSession(conversationId: 'conv-42');
      final serialized = await agent.serializeSession(session);
      final restored = await agent.deserializeSession(serialized) as ChatClientAgentSession;
      expect(restored.conversationId, 'conv-42');
    });

    test('serializeSessionCore throws for unsupported session type', () async {
      final agent = _makeAgent();
      final wrongSession = _OtherSession();
      await expectLater(
        () => agent.serializeSession(wrongSession),
        throwsArgumentError,
      );
    });

    test('deserializeSessionCore throws for non-String input', () async {
      final agent = _makeAgent();
      await expectLater(
        () => agent.deserializeSession(42),
        throwsArgumentError,
      );
    });

    test('createSessionCore returns a ChatClientAgentSession', () async {
      final agent = _makeAgent();
      final session = await agent.createSession();
      expect(session, isA<ChatClientAgentSession>());
    });
  });

  // ── AI context providers ───────────────────────────────────────────────────

  group('ChatClientAgent with AI context providers', () {
    test(
      'runAsyncInvokesAIContextProviderAndUsesResult',
      () async {
        final tool = _TestTool('provided-tool');
        final provider = _TestAIContextProvider(
          additionalMessages: [ChatMessage.fromText(ChatRole.user, 'context')],
          instructions: 'extra instructions',
          tools: [tool],
        );
        List<ChatMessage>? capturedMessages;
        ChatOptions? capturedOptions;
        final client = _ScriptedChatClient()
          ..onGetResponse = (messages, options, _) {
            capturedMessages = messages.toList();
            capturedOptions = options;
            return ChatResponse.fromMessage(
              ChatMessage.fromText(ChatRole.assistant, 'reply'),
            );
          };

        final agent = ChatClientAgent(
          client,
          options: ChatClientAgentOptions()
            ..useProvidedChatClientAsIs = true
            ..aiContextProviders = [provider],
        );

        await agent.runCore(
          [ChatMessage.fromText(ChatRole.user, 'original')],
          session: ChatClientAgentSession(),
        );

        expect(capturedMessages, isNotNull);
        expect(capturedOptions?.tools, contains(tool));
        expect(capturedOptions?.instructions, contains('extra instructions'));
      },
    );

    test('runAsyncInvokesMultipleAIContextProvidersInOrder', () async {
      final calls = <String>[];
      final provider1 = _RecordingAIContextProvider1(calls);
      final provider2 = _RecordingAIContextProvider2(calls);
      final client = _ScriptedChatClient();

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()
          ..useProvidedChatClientAsIs = true
          ..aiContextProviders = [provider1, provider2],
      );

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
      );

      expect(calls, ['p1', 'p2']);
    });

    test(
      'runStreamingAsyncInvokesAIContextProviderAndUsesResult',
      () async {
        final tool = _TestTool('streaming-tool');
        final provider = _TestAIContextProvider(tools: [tool]);
        ChatOptions? capturedOptions;
        final client = _ScriptedChatClient()
          ..onGetStreamingResponse = (_, options, _) async* {
            capturedOptions = options;
            yield ChatResponseUpdate.fromText(ChatRole.assistant, 'stream');
          };

        final agent = ChatClientAgent(
          client,
          options: ChatClientAgentOptions()
            ..useProvidedChatClientAsIs = true
            ..aiContextProviders = [provider],
        );

        await agent
            .runCoreStreaming(
              [ChatMessage.fromText(ChatRole.user, 'hi')],
              session: ChatClientAgentSession(),
            )
            .toList();

        expect(capturedOptions?.tools, contains(tool));
      },
    );
  });

  // ── Instructions merging ───────────────────────────────────────────────────

  group('ChatClientAgent instructions merging', () {
    test('runAsyncIncludesBaseInstructionsInOptions', () async {
      ChatOptions? capturedOptions;
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, options, _) {
          capturedOptions = options;
          return ChatResponse.fromMessage(
            ChatMessage.fromText(ChatRole.assistant, 'ok'),
          );
        };

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()
          ..useProvidedChatClientAsIs = true
          ..chatOptions = ChatOptions(instructions: 'base instructions'),
      );

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
      );

      expect(capturedOptions?.instructions, contains('base instructions'));
    });

    test('runAsync merges request instructions with agent instructions', () async {
      ChatOptions? capturedOptions;
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, options, _) {
          capturedOptions = options;
          return ChatResponse.fromMessage(
            ChatMessage.fromText(ChatRole.assistant, 'ok'),
          );
        };

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()
          ..useProvidedChatClientAsIs = true
          ..chatOptions = ChatOptions(instructions: 'agent-instr'),
      );
      final runOptions = ChatClientAgentRunOptions(
        chatOptions: ChatOptions(instructions: 'run-instr'),
      );

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
        options: runOptions,
      );

      // Both agent and run instructions should be merged with \n separator
      expect(capturedOptions?.instructions, contains('agent-instr'));
      expect(capturedOptions?.instructions, contains('run-instr'));
    });
  });

  // ── Chat options merging ───────────────────────────────────────────────────

  group('ChatClientAgent chat options merging', () {
    test('runAsyncPassesChatOptionsWhenUsingChatClientAgentRunOptions',
        () async {
      ChatOptions? capturedOptions;
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, options, _) {
          capturedOptions = options;
          return ChatResponse.fromMessage(
            ChatMessage.fromText(ChatRole.assistant, 'ok'),
          );
        };

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      final runOptions = ChatClientAgentRunOptions(
        chatOptions: ChatOptions(maxOutputTokens: 256),
      );

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
        options: runOptions,
      );

      expect(capturedOptions?.maxOutputTokens, 256);
    });

    test('runAsyncPassesNullChatOptionsWhenUsingRegularAgentRunOptions',
        () async {
      ChatOptions? capturedOptions;
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, options, _) {
          capturedOptions = options;
          return ChatResponse.fromMessage(
            ChatMessage.fromText(ChatRole.assistant, 'ok'),
          );
        };

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );

      await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
        options: AgentRunOptions(),
      );

      expect(capturedOptions, isNull);
    });
  });

  // ── Author name ────────────────────────────────────────────────────────────

  group('ChatClientAgent author name', () {
    test('runAsyncSetsAuthorNameOnAllResponseMessages', () async {
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) => ChatResponse(
              messages: [
                ChatMessage.fromText(ChatRole.assistant, 'a'),
                ChatMessage.fromText(ChatRole.assistant, 'b'),
              ],
            );

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()
          ..useProvidedChatClientAsIs = true
          ..name = 'TestAgent',
      );

      final response = await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
      );

      for (final msg in response.messages) {
        expect(msg.authorName, 'TestAgent');
      }
    });

    test('runAsyncNullNameDoesNotSetAuthorName', () async {
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) => ChatResponse(
              messages: [ChatMessage.fromText(ChatRole.assistant, 'reply')],
            );

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );

      final response = await agent.runCore(
        [ChatMessage.fromText(ChatRole.user, 'hi')],
        session: ChatClientAgentSession(),
      );

      expect(response.messages.single.authorName, isNull);
    });
  });

  // ── ChatOptions property ───────────────────────────────────────────────────

  group('ChatClientAgent.chatOptions', () {
    test('returnsNullWhenOptionsNull', () {
      final agent = ChatClientAgent(
        _ScriptedChatClient(),
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      expect(agent.chatOptions, isNull);
    });

    test('returnsNullWhenChatOptionsNull', () {
      final opts = ChatClientAgentOptions()..useProvidedChatClientAsIs = true;
      opts.chatOptions = null;
      final agent = ChatClientAgent(_ScriptedChatClient(), options: opts);
      expect(agent.chatOptions, isNull);
    });
  });

  // ── Builder convenience ────────────────────────────────────────────────────

  group('ChatClientAgent builder', () {
    test('constructorUsesOptionalParams', () {
      final tool = _TestTool('t');
      final agent = ChatClientBuilder(_ScriptedChatClient()).buildAIAgent(
        instructions: 'instr',
        name: 'N',
        description: 'D',
        tools: [tool],
      );
      expect(agent.name, 'N');
      expect(agent.description, 'D');
      expect(agent.instructions, 'instr');
      expect(agent.chatOptions!.tools, contains(tool));
    });

    test('chatOptionsCreatedWithInstructionsEvenWhenConstructorToolsNotProvided',
        () {
      final agent = ChatClientBuilder(_ScriptedChatClient()).buildAIAgent(
        instructions: 'instr-only',
      );
      expect(agent.instructions, 'instr-only');
    });

    test('optionsPropertiesNullOrDefaultWhenNotProvided', () {
      final agent = ChatClientAgent(
        _ScriptedChatClient(),
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );
      expect(agent.name, isNull);
      expect(agent.description, isNull);
    });
  });

  // ── Error propagation ──────────────────────────────────────────────────────

  group('ChatClientAgent error handling', () {
    test('runCoreRethrowsExceptionFromChatClient', () async {
      final client = _ScriptedChatClient()
        ..onGetResponse = (_, _, _) => throw Exception('downstream error');

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );

      await expectLater(
        () => agent.runCore(
          [ChatMessage.fromText(ChatRole.user, 'hi')],
          session: ChatClientAgentSession(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('runCoreStreamingRethrowsExceptionFromChatClient', () async {
      final client = _ScriptedChatClient()
        ..onGetStreamingResponse = (_, _, _) async* {
          throw Exception('streaming error');
        };

      final agent = ChatClientAgent(
        client,
        options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
      );

      await expectLater(
        () => agent
            .runCoreStreaming(
              [ChatMessage.fromText(ChatRole.user, 'hi')],
              session: ChatClientAgentSession(),
            )
            .toList(),
        throwsA(isA<Exception>()),
      );
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ChatClientAgent _makeAgent() => ChatClientAgent(
      _ScriptedChatClient(),
      options: ChatClientAgentOptions()..useProvidedChatClientAsIs = true,
    );

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _ScriptedChatClient implements ChatClient {
  _ScriptedChatClient({ChatClientMetadata? metadata}) : _metadata = metadata;

  final ChatClientMetadata? _metadata;

  ChatResponse Function(
    Iterable<ChatMessage>,
    ChatOptions?,
    CancellationToken?,
  )?
  onGetResponse;

  Stream<ChatResponseUpdate> Function(
    Iterable<ChatMessage>,
    ChatOptions?,
    CancellationToken?,
  )?
  onGetStreamingResponse;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      onGetResponse?.call(messages, options, cancellationToken) ??
      ChatResponse.fromMessage(
        ChatMessage.fromText(ChatRole.assistant, 'response'),
      );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final s = onGetStreamingResponse?.call(messages, options, cancellationToken);
    if (s == null) {
      yield ChatResponseUpdate.fromText(ChatRole.assistant, 'stream');
      return;
    }
    yield* s;
  }

  @override
  T? getService<T>({Object? key}) =>
      T == ChatClientMetadata ? _metadata as T? : null;

  @override
  void dispose() {}
}

class _TestAIContextProvider extends AIContextProvider {
  _TestAIContextProvider({
    this.additionalMessages,
    this.instructions,
    this.tools,
  });

  final List<ChatMessage>? additionalMessages;
  final String? instructions;
  final List<AITool>? tools;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async =>
      AIContext()
        ..messages = additionalMessages
        ..instructions = instructions
        ..tools = tools;
}

class _RecordingAIContextProvider1 extends AIContextProvider {
  _RecordingAIContextProvider1(this.calls);
  final List<String> calls;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    calls.add('p1');
    return AIContext();
  }
}

class _RecordingAIContextProvider2 extends AIContextProvider {
  _RecordingAIContextProvider2(this.calls);
  final List<String> calls;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    calls.add('p2');
    return AIContext();
  }
}

class _TestTool extends AITool {
  _TestTool(String name) : super(name: name);
}

class _OtherSession extends AgentSession {
  _OtherSession() : super(AgentSessionStateBag(null));
}
