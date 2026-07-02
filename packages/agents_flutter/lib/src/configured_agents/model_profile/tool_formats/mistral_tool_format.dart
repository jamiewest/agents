// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/ai.dart';

import 'tool_format.dart';

/// The Mistral v3 tool-calling convention: tools are advertised in an
/// `[AVAILABLE_TOOLS][…][/AVAILABLE_TOOLS]` block, the model replies with
/// `[TOOL_CALLS][{…}]`, and results are fed back inside
/// `[TOOL_RESULTS]…[/TOOL_RESULTS]`.
class MistralToolFormat extends ToolFormat {
  /// Creates a [MistralToolFormat].
  const MistralToolFormat();

  /// Marker that begins the tool-call JSON array.
  static const String toolCalls = '[TOOL_CALLS]';

  /// Markers wrapping the advertised tool list.
  static const String availableToolsStart = '[AVAILABLE_TOOLS]';

  /// Closing counterpart of [availableToolsStart].
  static const String availableToolsEnd = '[/AVAILABLE_TOOLS]';

  /// Markers wrapping a tool result fed back to the model.
  static const String toolResultsStart = '[TOOL_RESULTS]';

  /// Closing counterpart of [toolResultsStart].
  static const String toolResultsEnd = '[/TOOL_RESULTS]';

  @override
  String renderToolsSection(Iterable<AIFunctionDeclaration> tools) {
    final list = tools.toList();
    if (list.isEmpty) return '';
    final json = list
        .map(
          (t) => jsonEncode(<String, Object?>{
            'type': 'function',
            'function': <String, Object?>{
              'name': t.name,
              'description': t.description ?? '',
              if (t.parametersSchema != null) 'parameters': t.parametersSchema,
            },
          }),
        )
        .join(', ');
    return 'You may call the functions below. To call one or more, reply '
        'with $toolCalls followed by a JSON array of '
        '{"name": <name>, "arguments": <args>} objects.\n\n'
        '$availableToolsStart[$json]$availableToolsEnd';
  }

  @override
  String renderToolCallBlock(FunctionCallContent call) =>
      '$toolCalls[${jsonEncode(<String, Object?>{'name': call.name, 'arguments': call.arguments ?? const <String, Object?>{}})}]';

  @override
  String renderToolResultBlock(FunctionResultContent result) =>
      '$toolResultsStart${encodeToolResult(result.result)}$toolResultsEnd';

  @override
  ParsedToolTurn parseTurn(String generated) {
    final at = generated.indexOf(toolCalls);
    if (at < 0) {
      return ParsedToolTurn(text: generated.trim(), calls: const []);
    }
    final text = generated.substring(0, at).trim();
    final body = generated.substring(at + toolCalls.length).trim();
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw FormatException('Tool calls are not a JSON array', body);
    }
    final calls = <FunctionCallContent>[];
    for (final entry in decoded) {
      calls.add(functionCallFromJson(entry, calls.length));
    }
    return ParsedToolTurn(text: text, calls: calls);
  }

  @override
  String get callOpenMarker => toolCalls;
}
