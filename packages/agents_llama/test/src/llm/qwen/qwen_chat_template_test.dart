import 'package:agents_llama/agents_llama.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const template = QwenChatTemplate();
  const format = QwenChatFormat();

  group('QwenChatTemplate.render', () {
    test('wraps a tool result in a user turn (Qwen convention)', () {
      final prompt = template.render([
        ChatMessage.fromText(ChatRole.user, 'Weather?'),
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
        contains(
          '<|im_start|>user\n<tool_response>\n{temp: 20}\n</tool_response>'
          '<|im_end|>\n',
        ),
      );
    });

    test('groups consecutive tool results into one user turn', () {
      final prompt = template.render([
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(callId: 'a', name: 'x', result: '1'),
          ],
        ),
        ChatMessage(
          role: ChatRole.tool,
          contents: [
            FunctionResultContent(callId: 'b', name: 'y', result: '2'),
          ],
        ),
      ], addGenerationPrompt: false);

      expect(
        prompt.text,
        '<|im_start|>user\n'
        '<tool_response>\n1\n</tool_response>\n'
        '<tool_response>\n2\n</tool_response><|im_end|>\n',
      );
    });
  });

  group('QwenChatFormat (thinking + tools)', () {
    test('surfaces a <think> block as reasoning, then prose', () async {
      final updates = await format
          .decode(
            Stream<String>.value('<think>planning</think>The answer is 4.'),
          )
          .toList();

      final reasoning = updates
          .expand((u) => u.contents.whereType<TextReasoningContent>())
          .map((c) => c.text)
          .join();
      final text = updates
          .expand((u) => u.contents.whereType<TextContent>())
          .map((c) => c.text)
          .join();

      expect(reasoning, 'planning');
      expect(text, 'The answer is 4.');
    });

    test('decodes a tool call after thinking', () async {
      final updates = await format
          .decode(
            Stream<String>.value(
              '<think>need weather</think>'
              '<tool_call>\n{"name": "get_weather", "arguments": '
              '{"location": "Paris"}}\n</tool_call>',
            ),
          )
          .toList();

      final reasoning = updates
          .expand((u) => u.contents.whereType<TextReasoningContent>())
          .map((c) => c.text)
          .join();
      final calls = updates.expand(
        (u) => u.contents.whereType<FunctionCallContent>(),
      );

      expect(reasoning, 'need weather');
      expect(calls.single.name, 'get_weather');
      expect(calls.single.arguments, {'location': 'Paris'});
    });
  });
}
