import 'dart:typed_data';

import 'package:agents/agents.dart';
import 'package:agents_llama/agents_llama.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestFunction extends AIFunctionDeclaration {
  _TestFunction({required super.name});
}

final class _RecordingSession implements LlamaSession {
  _RecordingSession({this.stats});

  String? prompt;
  Iterable<Uint8List>? images;
  Iterable<String>? stopSequences;
  List<LlamaChatTurn>? turns;

  /// Stats reported through `onStats` after the token stream, when set.
  final LlamaGenerationStats? stats;

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.8,
    int? topK,
    double? topP,
    int? seed,
    List<String> stopSequences = const <String>[],
    List<Uint8List>? images,
    List<LlamaChatTurn>? turns,
    LlamaStatsCallback? onStats,
  }) {
    this.prompt = prompt;
    this.stopSequences = stopSequences;
    this.images = images;
    this.turns = turns;
    if (stats != null) onStats?.call(stats!);
    return Stream<String>.value('Hello!');
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('messagesWithRuntimeContext', () {
    test(
      'repositions text-only provider messages before the latest user turn',
      () {
        final prepared = messagesWithRuntimeContext([
          ChatMessage.fromText(ChatRole.user, 'Hi'),
          ChatMessage.fromText(
            ChatRole.user,
            '### Current todo list\n- none yet',
          ).withAgentRequestMessageSource(
            AgentRequestMessageSourceType.aiContextProvider,
            sourceId: 'TodoProvider',
          ),
        ], 'You are helpful.');

        // Volatile provider state stays out of the instructions so the
        // rendered system prompt (the KV-cache prefix) is turn-stable.
        expect(prepared.instructions, 'You are helpful.');
        final messages = prepared.messages.toList();
        expect(messages, hasLength(2));
        expect(messages.first.text, contains('Runtime context:'));
        expect(messages.first.text, contains('[TodoProvider]'));
        expect(messages.first.text, contains('### Current todo list'));
        expect(messages.last.text, 'Hi');
      },
    );

    test(
      'keeps provider messages with non-text content in the message list',
      () {
        final imageMessage =
            ChatMessage(
              role: ChatRole.user,
              contents: [
                TextContent('Image context'),
                DataContent(
                  Uint8List.fromList([1, 2, 3]),
                  mediaType: 'image/png',
                ),
              ],
            ).withAgentRequestMessageSource(
              AgentRequestMessageSourceType.aiContextProvider,
              sourceId: 'ImageProvider',
            );

        final prepared = messagesWithRuntimeContext([imageMessage], null);

        expect(prepared.messages.single, same(imageMessage));
        expect(prepared.instructions, isNull);
      },
    );
  });

  group('LlamaChatClient prompt preparation', () {
    test(
      'keeps tools while avoiding provider context as the final user turn',
      () async {
        final session = _RecordingSession();
        final client = LlamaChatClient(
          sessionProvider: () async => session,
          format: const Lfm2ChatFormat(),
          contextSize: 4096,
        );

        await client.getResponse(
          messages: [
            ChatMessage.fromText(ChatRole.user, 'Hi'),
            ChatMessage.fromText(
              ChatRole.user,
              '### Current todo list\n- none yet',
            ).withAgentRequestMessageSource(
              AgentRequestMessageSourceType.aiContextProvider,
              sourceId: 'TodoProvider',
            ),
          ],
          options: ChatOptions(
            instructions: 'You are a helpful assistant.',
            tools: [_TestFunction(name: 'TodoList_GetRemaining')],
          ),
          cancellationToken: CancellationToken.none,
        );

        final prompt = session.prompt!;
        expect(prompt, contains('Runtime context:'));
        expect(prompt, contains('### Current todo list'));
        expect(prompt, contains('List of tools: <|tool_list_start|>'));
        expect(prompt, contains('"name": "TodoList_GetRemaining"'));
        expect(prompt, contains('<|im_start|>user\nHi<|im_end|>'));
        expect(prompt, isNot(endsWith('Current todo list\n- none yet')));
        expect(
          prompt.lastIndexOf('<|im_start|>user\nHi<|im_end|>'),
          greaterThan(prompt.lastIndexOf('### Current todo list')),
        );
        expect(session.turns, isNull);
      },
    );

    test('passes structured turns to the session for image requests', () async {
      final session = _RecordingSession();
      final client = LlamaChatClient(
        sessionProvider: () async => session,
        format: const Lfm2ChatFormat(),
        contextSize: 4096,
      );
      final imageBytes = Uint8List.fromList([1, 2, 3]);

      await client.getResponse(
        messages: [
          ChatMessage.fromText(ChatRole.assistant, 'How can I help?'),
          ChatMessage(
            role: ChatRole.user,
            contents: [
              TextContent('What is in this picture?'),
              DataContent(imageBytes, mediaType: 'image/png'),
            ],
          ),
        ],
        options: ChatOptions(instructions: 'You are a helpful assistant.'),
        cancellationToken: CancellationToken.none,
      );

      expect(session.images, hasLength(1));
      final turns = session.turns;
      expect(turns, isNotNull);
      expect(turns!.map((turn) => turn.role), ['system', 'assistant', 'user']);
      expect(turns.first.text, 'You are a helpful assistant.');
      expect(turns[1].images, isEmpty);
      expect(turns.last.text, 'What is in this picture?');
      expect(turns.last.images.single, same(imageBytes));
    });
  });

  group('chatTurnsFromMessages', () {
    test('maps tool-role messages to user turns and skips non-image data', () {
      final turns = chatTurnsFromMessages([
        ChatMessage(
          role: ChatRole.tool,
          contents: [TextContent('{"result": 42}')],
        ),
        ChatMessage(
          role: ChatRole.user,
          contents: [
            DataContent(
              Uint8List.fromList([9, 9]),
              mediaType: 'application/pdf',
            ),
          ],
        ),
      ]);

      expect(turns.first.role, 'user');
      expect(turns.first.text, '{"result": 42}');
      expect(turns.last.images, isEmpty);
    });
  });

  group('formatResolver', () {
    test(
      'format resolved during session load applies to the first request',
      () async {
        final session = _RecordingSession();
        ChatFormat? resolved;
        final client = LlamaChatClient(
          sessionProvider: () async {
            // Simulates the host sniffing the GGUF while loading the model.
            resolved = const GemmaChatFormat();
            return session;
          },
          format: const Lfm2ChatFormat(),
          formatResolver: () => resolved,
          contextSize: 4096,
        );

        await client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'Hi')],
        );

        expect(session.prompt, contains('<|turn>'));
        expect(session.prompt, isNot(contains('<|im_start|>')));
      },
    );

    test('null resolver result falls back to the constructor format', () async {
      final session = _RecordingSession();
      final client = LlamaChatClient(
        sessionProvider: () async => session,
        format: const Lfm2ChatFormat(),
        formatResolver: () => null,
        contextSize: 4096,
      );

      await client.getResponse(
        messages: [ChatMessage.fromText(ChatRole.user, 'Hi')],
      );

      expect(session.prompt, contains('<|im_start|>'));
    });
  });

  group('usage reporting', () {
    test('emits a trailing usage-only update from runtime stats', () async {
      final session = _RecordingSession(
        stats: const LlamaGenerationStats(
          promptTokenCount: 100,
          cachedTokenCount: 60,
          generatedTokenCount: 25,
        ),
      );
      final client = LlamaChatClient(
        sessionProvider: () async => session,
        format: const Lfm2ChatFormat(),
        contextSize: 4096,
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'Hi')],
          )
          .toList();

      final usage = updates.last.usage;
      expect(usage, isNotNull);
      expect(usage!.inputTokenCount, 100);
      expect(usage.outputTokenCount, 25);
      expect(usage.totalTokenCount, 125);
      expect(usage.cachedInputTokenCount, 60);
    });

    test(
      'getResponse folds the trailing usage into ChatResponse.usage',
      () async {
        final session = _RecordingSession(
          stats: const LlamaGenerationStats(
            promptTokenCount: 40,
            cachedTokenCount: 0,
            generatedTokenCount: 8,
          ),
        );
        final client = LlamaChatClient(
          sessionProvider: () async => session,
          format: const Lfm2ChatFormat(),
          contextSize: 4096,
        );

        final response = await client.getResponse(
          messages: [ChatMessage.fromText(ChatRole.user, 'Hi')],
        );

        expect(response.usage?.inputTokenCount, 40);
        expect(response.usage?.outputTokenCount, 8);
        expect(response.text, 'Hello!');
      },
    );

    test('emits no usage update when the runtime reports none', () async {
      final session = _RecordingSession();
      final client = LlamaChatClient(
        sessionProvider: () async => session,
        format: const Lfm2ChatFormat(),
        contextSize: 4096,
      );

      final updates = await client
          .getStreamingResponse(
            messages: [ChatMessage.fromText(ChatRole.user, 'Hi')],
          )
          .toList();

      expect(updates.every((u) => u.usage == null), isTrue);
    });
  });
}
