import 'dart:typed_data';

import 'package:agents_llama/agents_llama.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';

/// Concrete [AIFunctionDeclaration] for tests (the base class is abstract).
class _TestFunction extends AIFunctionDeclaration {
  _TestFunction({
    required super.name,
    super.description,
    super.parametersSchema,
  });
}

void main() {
  const template = Lfm2ChatTemplate();

  group('Lfm2ChatTemplate.render', () {
    test('plain system + user turn', () {
      final prompt = template.render([
        ChatMessage.fromText(ChatRole.system, 'You are helpful.'),
        ChatMessage.fromText(ChatRole.user, 'Hi'),
      ]);

      expect(
        prompt.text,
        '<|im_start|>system\nYou are helpful.<|im_end|>\n'
        '<|im_start|>user\nHi<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
      expect(prompt.stopSequences, <String>['<|im_end|>']);
      expect(prompt.images, isEmpty);
    });

    test('user-only turn omits the system block', () {
      final prompt = template.render([
        ChatMessage.fromText(ChatRole.user, 'Hi'),
      ]);

      expect(
        prompt.text,
        '<|im_start|>user\nHi<|im_end|>\n<|im_start|>assistant\n',
      );
    });

    test('tools render a JSON declaration list in the system turn', () {
      final prompt = template.render(
        [ChatMessage.fromText(ChatRole.user, 'Weather?')],
        tools: [
          _TestFunction(
            name: 'get_weather',
            description: 'Get weather',
            parametersSchema: const {
              'type': 'object',
              'properties': {
                'location': {'type': 'string'},
              },
              'required': ['location'],
            },
          ),
        ],
      );

      expect(
        prompt.text,
        '<|im_start|>system\n'
        'List of tools: <|tool_list_start|>['
        '{"name": "get_weather", "description": "Get weather", '
        '"parameters": {"type": "object", '
        '"properties": {"location": {"type": "string"}}, '
        '"required": ["location"]}}'
        ']<|tool_list_end|><|im_end|>\n'
        '<|im_start|>user\nWeather?<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });

    test('image content emits a media marker and collects bytes', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final prompt = template.render([
        ChatMessage(
          role: ChatRole.user,
          contents: [
            TextContent('What is this?'),
            DataContent(bytes, mediaType: 'image/png'),
          ],
        ),
      ]);

      expect(
        prompt.text,
        '<|im_start|>user\nWhat is this?<__media__><|im_end|>\n'
        '<|im_start|>assistant\n',
      );
      expect(prompt.images, [bytes]);
    });

    test('assistant tool call replays as a Pythonic call block', () {
      final prompt = template.render([
        ChatMessage.fromText(ChatRole.user, 'Weather in Paris?'),
        ChatMessage(
          role: ChatRole.assistant,
          contents: [
            FunctionCallContent(
              callId: 'call_0',
              name: 'get_weather',
              arguments: const {'location': 'Paris'},
            ),
          ],
        ),
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(
              callId: 'call_0',
              name: 'get_weather',
              result: const {'temp': 20},
            ),
          ],
        ),
      ], addGenerationPrompt: false);

      expect(
        prompt.text,
        '<|im_start|>user\nWeather in Paris?<|im_end|>\n'
        '<|im_start|>assistant\n'
        '<|tool_call_start|>[get_weather(location="Paris")]<|tool_call_end|>'
        '<|im_end|>\n'
        '<|im_start|>tool\n'
        '<|tool_response_start|>{"temp": 20}<|tool_response_end|><|im_end|>\n',
      );
    });
  });

  group('Lfm2ChatTemplate.parse', () {
    test('parses a single Pythonic tool call', () {
      final turn = template.parse(
        '<|tool_call_start|>[get_weather(location="Paris")]<|tool_call_end|>',
      );

      expect(turn.text, isEmpty);
      expect(turn.calls, hasLength(1));
      expect(turn.calls.single.name, 'get_weather');
      expect(turn.calls.single.arguments, {'location': 'Paris'});
    });

    test('separates leading prose from the tool call', () {
      final turn = template.parse(
        'Let me check. <|tool_call_start|>[f(x=1)]<|tool_call_end|>',
      );

      expect(turn.text, 'Let me check.');
      expect(turn.calls.single.name, 'f');
      expect(turn.calls.single.arguments, {'x': 1});
    });

    test('parses multiple calls and literal types', () {
      final turn = template.parse(
        '<|tool_call_start|>['
        'a(n=1, flag=True, missing=None), '
        'b(items=[1, 2], who="bob")'
        ']<|tool_call_end|>',
      );

      expect(turn.calls, hasLength(2));
      expect(turn.calls[0].name, 'a');
      expect(turn.calls[0].arguments, {'n': 1, 'flag': true, 'missing': null});
      expect(turn.calls[1].name, 'b');
      expect(turn.calls[1].arguments, {
        'items': [1, 2],
        'who': 'bob',
      });
    });

    test('plain prose yields no calls', () {
      final turn = template.parse('Just a normal answer.');
      expect(turn.text, 'Just a normal answer.');
      expect(turn.calls, isEmpty);
    });
  });
}
