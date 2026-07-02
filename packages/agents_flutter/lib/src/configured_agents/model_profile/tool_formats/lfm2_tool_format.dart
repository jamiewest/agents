// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/ai.dart';

import 'tool_format.dart';

/// How Liquid-family prompts wrap tool declarations and tool responses.
enum LfmToolTagStyle {
  /// LFM2 style: wrap definitions and responses in Liquid tool tags.
  lfm2,

  /// LFM2.5 style: use plain JSON text for definitions and responses.
  lfm25,
}

/// The Liquid LFM tool-calling convention: calls wrapped in
/// `<|tool_call_start|>`/`<|tool_call_end|>` tags with the tool list
/// advertised in the system turn (Liquid tags for LFM2, plain JSON for
/// LFM2.5).
///
/// The system instructions request JSON call syntax; the Pythonic form
/// LFM2 emits locally by default (`[name(arg="value")]`) is not parsed
/// here — remote fallback use always instructs JSON.
class Lfm2ToolFormat extends ToolFormat {
  /// Creates an [Lfm2ToolFormat] for the given tag [style].
  const Lfm2ToolFormat({this.style = LfmToolTagStyle.lfm2});

  /// Whether declarations/results use LFM2 tags or LFM2.5 plain JSON.
  final LfmToolTagStyle style;

  /// Tags wrapping a tool call in generated output.
  static const String toolCallStart = '<|tool_call_start|>';

  /// Closing counterpart of [toolCallStart].
  static const String toolCallEnd = '<|tool_call_end|>';

  /// Tags wrapping the advertised tool list (LFM2 style).
  static const String toolListStart = '<|tool_list_start|>';

  /// Closing counterpart of [toolListStart].
  static const String toolListEnd = '<|tool_list_end|>';

  /// Tags wrapping a tool result (LFM2 style).
  static const String toolResponseStart = '<|tool_response_start|>';

  /// Closing counterpart of [toolResponseStart].
  static const String toolResponseEnd = '<|tool_response_end|>';

  @override
  String renderToolsSection(Iterable<AIFunctionDeclaration> tools) {
    final list = tools.toList();
    if (list.isEmpty) return '';
    final json = '[${list.map(toolDeclarationJson).join(', ')}]';
    final wrapped = switch (style) {
      LfmToolTagStyle.lfm2 => '$toolListStart$json$toolListEnd',
      LfmToolTagStyle.lfm25 => json,
    };
    return 'List of tools: $wrapped\n'
        'To call a tool, wrap a JSON object of the form '
        '{"name": <name>, "arguments": <args>} in '
        '$toolCallStart and $toolCallEnd. Output function calls as JSON.';
  }

  @override
  String renderToolCallBlock(FunctionCallContent call) =>
      '$toolCallStart${jsonEncode(<String, Object?>{'name': call.name, 'arguments': call.arguments ?? const <String, Object?>{}})}$toolCallEnd';

  @override
  String renderToolResultBlock(FunctionResultContent result) {
    final encoded = encodeToolResult(result.result);
    return switch (style) {
      LfmToolTagStyle.lfm2 => '$toolResponseStart$encoded$toolResponseEnd',
      LfmToolTagStyle.lfm25 => encoded,
    };
  }

  @override
  ParsedToolTurn parseTurn(String generated) {
    final calls = <FunctionCallContent>[];
    final text = StringBuffer();
    var cursor = 0;
    while (cursor < generated.length) {
      final open = generated.indexOf(toolCallStart, cursor);
      if (open < 0) {
        text.write(generated.substring(cursor));
        break;
      }
      text.write(generated.substring(cursor, open));
      final bodyStart = open + toolCallStart.length;
      final close = generated.indexOf(toolCallEnd, bodyStart);
      final bodyEnd = close < 0 ? generated.length : close;
      final body = generated.substring(bodyStart, bodyEnd).trim();
      final decoded = jsonDecode(body);
      final entries = decoded is List ? decoded : <Object?>[decoded];
      for (final entry in entries) {
        calls.add(functionCallFromJson(entry, calls.length));
      }
      cursor = close < 0 ? generated.length : close + toolCallEnd.length;
    }
    return ParsedToolTurn(text: text.toString().trim(), calls: calls);
  }

  @override
  String get callOpenMarker => toolCallStart;
}
