// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Declaration extends AIFunctionDeclaration {
  _Declaration({
    required super.name,
    super.description,
    super.parametersSchema,
  });
}

void main() {
  final weather = _Declaration(
    name: 'get_weather',
    description: 'Gets the weather.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'location': {'type': 'string'},
      },
    },
  );

  final call = FunctionCallContent(
    callId: 'call_0',
    name: 'get_weather',
    arguments: const {'location': 'Seattle'},
  );

  final result = FunctionResultContent(
    callId: 'call_0',
    name: 'get_weather',
    result: const {'temperature': 55},
  );

  group('HermesToolFormat', () {
    const format = HermesToolFormat();

    test('renders tools inside <tools> tags', () {
      final section = format.renderToolsSection([weather]);
      expect(section, contains('<tools>'));
      expect(section, contains('"get_weather"'));
      expect(section, contains('</tools>'));
      expect(format.renderToolsSection(const []), isEmpty);
    });

    test('round-trips a tool call', () {
      final block = format.renderToolCallBlock(call);
      final turn = format.parseTurn('Checking.\n$block');
      expect(turn.text, 'Checking.');
      expect(turn.calls, hasLength(1));
      expect(turn.calls.single.name, 'get_weather');
      expect(turn.calls.single.arguments, {'location': 'Seattle'});
    });

    test('parses multiple calls in one turn', () {
      final block = format.renderToolCallBlock(call);
      final turn = format.parseTurn('$block\n$block');
      expect(turn.calls, hasLength(2));
      expect(turn.calls[1].callId, isNot(turn.calls[0].callId));
    });

    test('renders results in <tool_response> tags', () {
      final block = format.renderToolResultBlock(result);
      expect(block, startsWith('<tool_response>'));
      expect(block, contains('"temperature":55'));
      expect(block, endsWith('</tool_response>'));
    });

    test('throws on malformed call JSON', () {
      expect(
        () => format.parseTurn('<tool_call>{oops</tool_call>'),
        throwsFormatException,
      );
    });
  });

  group('Llama3ToolFormat', () {
    const format = Llama3ToolFormat();

    test('round-trips a python_tag call', () {
      final block = format.renderToolCallBlock(call);
      expect(block, startsWith('<|python_tag|>'));
      final turn = format.parseTurn(block);
      expect(turn.calls.single.name, 'get_weather');
      expect(turn.calls.single.arguments, {'location': 'Seattle'});
    });

    test('accepts an untagged bare-JSON call turn', () {
      final turn = format.parseTurn(
        '{"name": "get_weather", "parameters": {"location": "Seattle"}}',
      );
      expect(turn.calls.single.name, 'get_weather');
      expect(turn.text, isEmpty);
    });

    test('plain prose stays prose', () {
      final turn = format.parseTurn('The weather is nice.');
      expect(turn.calls, isEmpty);
      expect(turn.text, 'The weather is nice.');
    });
  });

  group('MistralToolFormat', () {
    const format = MistralToolFormat();

    test('round-trips a [TOOL_CALLS] array', () {
      final block = format.renderToolCallBlock(call);
      expect(block, startsWith('[TOOL_CALLS]'));
      final turn = format.parseTurn(block);
      expect(turn.calls.single.name, 'get_weather');
    });

    test('parses multiple calls from one array', () {
      final turn = format.parseTurn(
        '[TOOL_CALLS][{"name": "a", "arguments": {}}, '
        '{"name": "b", "arguments": {"x": 1}}]',
      );
      expect(turn.calls, hasLength(2));
      expect(turn.calls[1].name, 'b');
      expect(turn.calls[1].arguments, {'x': 1});
    });

    test('throws when the body is not an array', () {
      expect(
        () => format.parseTurn('[TOOL_CALLS]{"name": "a"}'),
        throwsFormatException,
      );
    });
  });

  group('Lfm2ToolFormat', () {
    test('lfm2 style wraps declarations and results in Liquid tags', () {
      const format = Lfm2ToolFormat();
      expect(
        format.renderToolsSection([weather]),
        contains('<|tool_list_start|>'),
      );
      expect(
        format.renderToolResultBlock(result),
        startsWith('<|tool_response_start|>'),
      );
    });

    test('lfm2.5 style uses plain JSON', () {
      const format = Lfm2ToolFormat(style: LfmToolTagStyle.lfm25);
      expect(
        format.renderToolsSection([weather]),
        isNot(contains('<|tool_list_start|>')),
      );
      expect(
        format.renderToolResultBlock(result),
        isNot(contains('<|tool_response_start|>')),
      );
    });

    test('round-trips a tagged call', () {
      const format = Lfm2ToolFormat();
      final turn = format.parseTurn(format.renderToolCallBlock(call));
      expect(turn.calls.single.name, 'get_weather');
    });

    test('parses a JSON array of calls in one block', () {
      const format = Lfm2ToolFormat();
      final turn = format.parseTurn(
        '<|tool_call_start|>[{"name": "a", "arguments": {}}, '
        '{"name": "b", "arguments": {}}]<|tool_call_end|>',
      );
      expect(turn.calls, hasLength(2));
    });
  });

  group('ToolFormat.decode', () {
    const format = HermesToolFormat();

    test('splits prose from a call with the marker across chunks', () async {
      final updates = await format
          .decode(
            Stream.fromIterable([
              'Let me check. <tool',
              '_call>\n{"name": "get_weather", ',
              '"arguments": {"location": "Seattle"}}\n</tool_call>',
            ]),
          )
          .toList();

      final text = updates
          .expand((u) => u.contents)
          .whereType<TextContent>()
          .map((c) => c.text)
          .join();
      final calls = updates
          .expand((u) => u.contents)
          .whereType<FunctionCallContent>()
          .toList();

      expect(text.trim(), 'Let me check.');
      expect(calls, hasLength(1));
      expect(calls.single.arguments, {'location': 'Seattle'});
    });

    test('text and calls are never mixed in one update', () async {
      final updates = await format
          .decode(
            Stream.fromIterable([
              'Hi <tool_call>{"name": "a", "arguments": {}}</tool_call>',
            ]),
          )
          .toList();
      for (final update in updates) {
        final hasCall = update.contents.any((c) => c is FunctionCallContent);
        final hasText = update.contents.any((c) => c is TextContent);
        expect(hasCall && hasText, isFalse);
      }
    });

    test('malformed buffered tail falls back to raw text', () async {
      final updates = await format
          .decode(Stream.fromIterable(['<tool_call>{broken']))
          .toList();
      final text = updates
          .expand((u) => u.contents)
          .whereType<TextContent>()
          .map((c) => c.text)
          .join();
      expect(text, '<tool_call>{broken');
      expect(
        updates.expand((u) => u.contents).whereType<FunctionCallContent>(),
        isEmpty,
      );
    });
  });

  group('ThinkTagFilter', () {
    test('splits reasoning from prose across chunk boundaries', () {
      final filter = ThinkTagFilter();
      final contents = <AIContent>[
        ...filter.add('<thi'),
        ...filter.add('nk>pondering</th'),
        ...filter.add('ink>The answer is 4.'),
        ...filter.flush(),
      ];

      final reasoning = contents
          .whereType<TextReasoningContent>()
          .map((c) => c.text)
          .join();
      final text = contents.whereType<TextContent>().map((c) => c.text).join();
      expect(reasoning, 'pondering');
      expect(text, 'The answer is 4.');
    });

    test('unterminated think block surfaces as reasoning', () {
      final filter = ThinkTagFilter();
      final contents = <AIContent>[
        ...filter.add('<think>still going'),
        ...filter.flush(),
      ];
      expect(contents.whereType<TextContent>(), isEmpty);
      expect(
        contents.whereType<TextReasoningContent>().map((c) => c.text).join(),
        'still going',
      );
    });

    test('passes plain text through', () {
      final filter = ThinkTagFilter();
      final contents = <AIContent>[
        ...filter.add('Just text, no tags.'),
        ...filter.flush(),
      ];
      expect(contents.whereType<TextReasoningContent>(), isEmpty);
      expect(
        contents.whereType<TextContent>().map((c) => c.text).join(),
        'Just text, no tags.',
      );
    });
  });
}
