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
  String? prompt;
  Iterable<Uint8List>? images;
  Iterable<String>? stopSequences;
  List<LlamaChatTurn>? turns;

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
  }) {
    this.prompt = prompt;
    this.stopSequences = stopSequences;
    this.images = images;
    this.turns = turns;
    return Stream<String>.value('Hello!');
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('messagesWithRuntimeContext', () {
    test('folds text-only provider messages into runtime context', () {
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

      expect(prepared.messages, hasLength(1));
      expect(prepared.messages.single.text, 'Hi');
      expect(prepared.instructions, contains('Runtime context:'));
      expect(prepared.instructions, contains('[TodoProvider]'));
      expect(prepared.instructions, contains('### Current todo list'));
    });

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
}
