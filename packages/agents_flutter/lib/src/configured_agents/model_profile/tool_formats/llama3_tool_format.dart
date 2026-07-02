// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/ai.dart';

import 'tool_format.dart';

/// The Llama 3.1 `python_tag` JSON tool-calling convention: tools are
/// advertised as a JSON array in the system instructions and the model
/// replies with `<|python_tag|>{"name":…,"parameters":{…}}`.
///
/// [parseTurn] also accepts a bare leading JSON object (the untagged mode
/// some checkpoints emit); the streaming [decode] keys on the tag only, so
/// an untagged streamed call surfaces as prose.
class Llama3ToolFormat extends ToolFormat {
  /// Creates a [Llama3ToolFormat].
  const Llama3ToolFormat();

  /// Marker that prefixes a tool call.
  static const String pythonTag = '<|python_tag|>';

  @override
  String renderToolsSection(Iterable<AIFunctionDeclaration> tools) {
    final list = tools.toList();
    if (list.isEmpty) return '';
    final json = list.map(toolDeclarationJson).join(', ');
    return 'You have access to the following functions. To call one, '
        'reply with a JSON object of the form '
        '{"name": <name>, "parameters": <args>} prefixed by $pythonTag.'
        '\n\n[$json]';
  }

  @override
  String renderToolCallBlock(FunctionCallContent call) =>
      pythonTag +
      jsonEncode(<String, Object?>{
        'name': call.name,
        'parameters': call.arguments ?? const <String, Object?>{},
      });

  @override
  String renderToolResultBlock(FunctionResultContent result) =>
      encodeToolResult(result.result);

  @override
  ParsedToolTurn parseTurn(String generated) {
    var at = generated.indexOf(pythonTag);
    var bodyStart = at + pythonTag.length;
    if (at < 0) {
      // Untagged mode: a turn that is exactly one JSON call object.
      final trimmed = generated.trim();
      if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
        return ParsedToolTurn(text: trimmed, calls: const []);
      }
      at = 0;
      bodyStart = 0;
    }
    final text = generated.substring(0, at).trim();
    final body = bodyStart == 0
        ? generated.trim()
        : generated.substring(bodyStart).trim();
    return ParsedToolTurn(
      text: text,
      calls: <FunctionCallContent>[functionCallFromJson(jsonDecode(body), 0)],
    );
  }

  @override
  String get callOpenMarker => pythonTag;
}
