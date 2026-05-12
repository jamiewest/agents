// ignore_for_file: avoid_print
/// Demonstrates the core patterns of the agents package.
///
/// [EchoChatClient] is a self-contained stub that echoes user messages back.
/// Replace it with a real ChatClient (e.g. backed by OpenAI, Azure OpenAI,
/// or another provider) to connect to an actual AI model.
library;

import 'dart:io';

import 'package:agents/src/ai/ai_agent_builder.dart';
import 'package:agents/src/ai/chat_client/chat_client_extensions.dart';
import 'package:agents/src/ai/logging_agent.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

Future<void> main() async {
  // ── 1. Create an agent ──────────────────────────────────────────────────
  //
  // Wrap any ChatClient with asAIAgent(). Swap EchoChatClient for a real
  // provider-backed ChatClient to connect to an LLM.
  final baseAgent = EchoChatClient().asAIAgent(
    name: 'Assistant',
    instructions: 'You are a concise, helpful assistant.',
  );

  // ── 2. Add middleware via AIAgentBuilder ─────────────────────────────────
  //
  // AIAgentBuilder composes decorator agents. Here we add LoggingAgent so
  // every run/runStreaming call is wrapped with structured log output.
  final loggerFactory = NullLoggerFactory.instance;
  final logger = loggerFactory.createLogger('Assistant');

  final agent = AIAgentBuilder(
    innerAgent: baseAgent,
  ).use(agentFactory: (inner) => LoggingAgent(inner, logger)).build();

  // ── 3. Multi-turn conversation with a session ────────────────────────────
  //
  // AgentSession carries chat history across turns automatically.
  print('=== Multi-turn conversation ===');
  final session = await agent.createSession();

  final r1 = await agent.run(
    session,
    null,
    cancellationToken: CancellationToken.none,
    message: 'My name is Ada.',
  );
  print('Assistant: ${r1.text}');

  final r2 = await agent.run(
    session,
    null,
    cancellationToken: CancellationToken.none,
    message: 'What is my name?',
  );
  print('Assistant: ${r2.text}');

  // ── 4. Streaming ─────────────────────────────────────────────────────────
  print('\n=== Streaming ===');
  final streamSession = await agent.createSession();

  stdout.write('Assistant: ');
  await for (final update in agent.runStreaming(
    streamSession,
    null,
    cancellationToken: CancellationToken.none,
    message: 'Count to three.',
  )) {
    stdout.write(update.text);
  }
  stdout.writeln();

  // ── 5. Session serialisation ─────────────────────────────────────────────
  print('\n=== Session serialisation ===');
  final serialised = await agent.serializeSession(session);
  print('Serialised: $serialised');
  final restored = await agent.deserializeSession(serialised);
  print('Restored session type: ${restored.runtimeType}');
}

// ── Stub ChatClient ─────────────────────────────────────────────────────────
//
// EchoChatClient is a minimal ChatClient that echoes the last user message.
// It exists solely so this example compiles and runs without a real API key.
// Replace it with your provider's ChatClient implementation in production.

class EchoChatClient implements ChatClient {
  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final reply = _buildReply(messages, options);
    return ChatResponse.fromMessage(
      ChatMessage.fromText(ChatRole.assistant, reply),
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final reply = _buildReply(messages, options);
    for (final word in reply.split(' ')) {
      yield ChatResponseUpdate.fromText(ChatRole.assistant, '$word ');
    }
  }

  @override
  T? getService<T>({Object? key}) => null;

  @override
  void dispose() {}

  String _buildReply(Iterable<ChatMessage> messages, ChatOptions? options) {
    final system = options?.instructions;
    final last = messages.lastWhere(
      (m) => m.role == ChatRole.user,
      orElse: () => ChatMessage.fromText(ChatRole.user, ''),
    );
    final userText = last.text;
    final prefix = system != null ? '[$system] ' : '';
    return '${prefix}You said: "$userText"';
  }
}
