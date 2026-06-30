import 'package:agents_llama/agents_llama.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveChatFormat', () {
    test('resolves each known family to its format', () {
      expect(resolveChatFormat('gemma'), isA<GemmaChatFormat>());
      expect(resolveChatFormat('lfm2'), isA<Lfm2ChatFormat>());
      expect(resolveChatFormat('lfm2-vl'), isA<Lfm2ChatFormat>());
      expect(resolveChatFormat('chatml'), isA<ChatmlChatFormat>());
      expect(resolveChatFormat('llama3'), isA<Llama3ChatFormat>());
      expect(resolveChatFormat('mistral'), isA<MistralChatFormat>());
      expect(resolveChatFormat('qwen'), isA<QwenChatFormat>());
    });

    test('an unset name resolves to the default (gemma)', () {
      expect(resolveChatFormat(null), isA<GemmaChatFormat>());
      expect(resolveChatFormat(''), isA<GemmaChatFormat>());
    });

    test('an unknown name resolves to null', () {
      expect(resolveChatFormat('nope'), isNull);
    });

    test('supportedChatFormatNames lists every family', () {
      expect(
        supportedChatFormatNames,
        containsAll(<String>[
          'gemma',
          'lfm2',
          'lfm2-vl',
          'chatml',
          'llama3',
          'mistral',
          'qwen',
        ]),
      );
    });
  });
}
