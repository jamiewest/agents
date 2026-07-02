// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The prompt-injected tool-calling seam used when an OpenAI-compatible
/// model has no reliable native `tools` support.
///
/// Unlike the local llama chat formats, a remote server applies the model's
/// role template itself — only the tool markup travels inside message
/// content. A [ToolFormat] therefore renders tool declarations into the
/// system instructions, rewrites past calls/results as plain text, and
/// parses the family's tool-call markers back out of generated text.
library;

import 'dart:convert';

import 'package:extensions/ai.dart';

import 'tool_call_stream_decoder.dart';

/// Prose plus any tool calls extracted from one generated model turn.
class ParsedToolTurn {
  /// Creates a [ParsedToolTurn].
  const ParsedToolTurn({required this.text, required this.calls});

  /// User-visible prose, with any tool-call markup removed.
  final String text;

  /// Tool calls the model requested, in emission order.
  final List<FunctionCallContent> calls;
}

/// Renders and parses one model family's prompt-injected tool markup.
abstract class ToolFormat {
  /// Creates a [ToolFormat].
  const ToolFormat();

  /// The system-instructions section advertising [tools].
  ///
  /// Returns an empty string when [tools] is empty.
  String renderToolsSection(Iterable<AIFunctionDeclaration> tools);

  /// One past assistant tool call, rendered back into assistant text.
  String renderToolCallBlock(FunctionCallContent call);

  /// One past tool result, rendered as text fed back to the model.
  String renderToolResultBlock(FunctionResultContent result);

  /// Parses a complete generated turn into prose plus tool calls.
  ///
  /// Throws [FormatException] when a call body is malformed so callers can
  /// fall back to surfacing the raw text.
  ParsedToolTurn parseTurn(String generated);

  /// The literal marker that begins a tool-call region in generated text.
  String get callOpenMarker;

  /// Creates a fresh incremental decoder for one response stream.
  ToolCallStreamDecoder newStreamDecoder() =>
      ToolCallStreamDecoder(openMarker: callOpenMarker, parse: parseTurn);

  /// Splits streamed text into prose and tool-call updates.
  ///
  /// Text and tool calls are emitted in separate updates:
  /// `FunctionInvokingChatClient` suppresses updates carrying calls, so
  /// combining them would drop the prose.
  Stream<ChatResponseUpdate> decode(Stream<String> text) async* {
    final decoder = newStreamDecoder();
    await for (final piece in text) {
      final prose = decoder.add(piece);
      if (prose.isNotEmpty) {
        yield ChatResponseUpdate.fromText(ChatRole.assistant, prose);
      }
    }
    final turn = decoder.finish();
    if (turn.text.isNotEmpty) {
      yield ChatResponseUpdate.fromText(ChatRole.assistant, turn.text);
    }
    if (turn.calls.isNotEmpty) {
      yield ChatResponseUpdate(
        role: ChatRole.assistant,
        contents: List<AIContent>.of(turn.calls),
      );
    }
  }
}

/// Renders one tool declaration as the JSON object most families expect:
/// `{"name": …, "description": …, "parameters": {…}}`.
String toolDeclarationJson(AIFunctionDeclaration tool) =>
    jsonEncode(<String, Object?>{
      'name': tool.name,
      'description': tool.description ?? '',
      if (tool.parametersSchema != null) 'parameters': tool.parametersSchema,
    });

/// Encodes a tool result value as text for feeding back to the model.
String encodeToolResult(Object? result) =>
    result is String ? result : jsonEncode(result);

/// Parses one `{"name": …, "arguments"|"parameters": {…}}` object into a
/// [FunctionCallContent] with a synthetic sequential call id.
///
/// Throws [FormatException] when [decoded] is not such an object.
FunctionCallContent functionCallFromJson(Object? decoded, int index) {
  if (decoded is! Map) {
    throw const FormatException('Tool call is not a JSON object');
  }
  final name = decoded['name'];
  if (name is! String || name.isEmpty) {
    throw const FormatException('Tool call has no "name"');
  }
  final args = (decoded['arguments'] ?? decoded['parameters']) as Map?;
  return FunctionCallContent(
    callId: 'call_$index',
    name: name,
    arguments: args?.cast<String, Object?>() ?? const <String, Object?>{},
  );
}
