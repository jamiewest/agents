// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/ai.dart';

import 'tool_format.dart';

/// The Hermes / Qwen tool-calling convention: tools advertised inside
/// `<tools></tools>` XML tags, calls returned as
/// `<tool_call>{"name":…,"arguments":{…}}</tool_call>` blocks, and results
/// fed back in `<tool_response>` blocks.
///
/// Serves the `qwen` and `chatml` format names, and `gemma` for remote
/// models: Gemma's local llama.cpp template uses a bespoke argument grammar
/// tied to its trained control tokens, which remote instruction-following
/// gemma models don't expose — the Hermes JSON convention is what they
/// reliably produce when instructed.
class HermesToolFormat extends ToolFormat {
  /// Creates a [HermesToolFormat].
  const HermesToolFormat();

  /// Tags wrapping a single tool call in generated output.
  static const String toolCallOpen = '<tool_call>';

  /// Closing counterpart of [toolCallOpen].
  static const String toolCallClose = '</tool_call>';

  /// Tags wrapping a tool result fed back to the model.
  static const String toolResponseOpen = '<tool_response>';

  /// Closing counterpart of [toolResponseOpen].
  static const String toolResponseClose = '</tool_response>';

  @override
  String renderToolsSection(Iterable<AIFunctionDeclaration> tools) {
    final list = tools.toList();
    if (list.isEmpty) return '';
    final signatures = list.map(toolDeclarationJson).join('\n');
    return '# Tools\n\n'
        'You may call one or more functions to assist with the user '
        'query.\n\n'
        'You are provided with function signatures within '
        '<tools></tools> XML tags:\n'
        '<tools>\n$signatures\n</tools>\n\n'
        'For each function call, return a json object with function name '
        'and arguments within <tool_call></tool_call> XML tags:\n'
        '$toolCallOpen\n'
        '{"name": <function-name>, "arguments": <args-json-object>}\n'
        '$toolCallClose';
  }

  @override
  String renderToolCallBlock(FunctionCallContent call) {
    final payload = <String, Object?>{
      'name': call.name,
      'arguments': call.arguments ?? const <String, Object?>{},
    };
    return '$toolCallOpen\n${jsonEncode(payload)}\n$toolCallClose';
  }

  @override
  String renderToolResultBlock(FunctionResultContent result) =>
      '$toolResponseOpen\n${encodeToolResult(result.result)}'
      '\n$toolResponseClose';

  @override
  ParsedToolTurn parseTurn(String generated) {
    final calls = <FunctionCallContent>[];
    final text = StringBuffer();
    var cursor = 0;
    while (cursor < generated.length) {
      final open = generated.indexOf(toolCallOpen, cursor);
      if (open < 0) {
        text.write(generated.substring(cursor));
        break;
      }
      text.write(generated.substring(cursor, open));
      final bodyStart = open + toolCallOpen.length;
      final close = generated.indexOf(toolCallClose, bodyStart);
      final bodyEnd = close < 0 ? generated.length : close;
      final body = generated.substring(bodyStart, bodyEnd).trim();
      calls.add(functionCallFromJson(jsonDecode(body), calls.length));
      cursor = close < 0 ? generated.length : close + toolCallClose.length;
    }
    return ParsedToolTurn(text: text.toString().trim(), calls: calls);
  }

  @override
  String get callOpenMarker => toolCallOpen;
}
