import 'dart:convert';

import 'package:extensions/ai.dart';

import 'streaming_tool_call_result_pair_matcher.dart';

/// Renders chat content to plain text and extracts embedded JSON for the
/// Magentic manager prompts.
extension MagenticChatMessageListExtensions on List<ChatMessage> {
  /// Renders the contents of all messages to a single text block.
  String getText() {
    if (isEmpty) {
      return '';
    }

    final builder = StringBuffer();
    final pairMatcher = StreamingToolCallResultPairMatcher();
    for (final message in this) {
      _processContents(builder, message.contents, pairMatcher);
    }
    return builder.toString();
  }
}

/// Extracts the first balanced JSON object embedded in a [ChatMessage].
extension MagenticChatMessageExtensions on ChatMessage {
  /// Extracts the first JSON object found in this message's text.
  Map<String, Object?> extractJson() => extractJsonFromText(text);
}

void _processContents(
  StringBuffer builder,
  List<AIContent> contents,
  StreamingToolCallResultPairMatcher pairMatcher,
) {
  for (final content in contents) {
    switch (content) {
      case TextContent():
        builder.writeln(content.text);
      case ErrorContent():
        final code = content.errorCode != null
            ? '(Code=${content.errorCode})'
            : '';
        builder.writeln('[ERROR$code]');
        builder.writeln(content.message);
        if (content.details != null) {
          builder
            ..write('Details:')
            ..writeln(content.details);
        }
      case FunctionCallContent():
        pairMatcher.collectFunctionCall(content);
      case FunctionResultContent():
        final name = pairMatcher.resolveFunctionCall(content);
        final result = content.result?.toString() ?? '';
        builder
          ..writeln("[Tool Call '${name ?? content.callId}' Result]")
          ..writeln(result);
      case McpServerToolCallContent():
        pairMatcher.collectMcpServerToolCall(content);
      case MCPServerToolResultContent():
        final outputs = content.outputs;
        if (outputs != null && outputs.isNotEmpty) {
          final name = pairMatcher.resolveMcpServerToolCall(content);
          final label = name ?? content.callId;
          builder.writeln("[Start MCP Server Tool Call '$label' Results]");
          _processContents(
            builder,
            outputs,
            StreamingToolCallResultPairMatcher(),
          );
          builder.writeln("[End MCP Server Tool Call '$label']");
        }
      case TextReasoningContent():
        if (content.text.trim().isNotEmpty) {
          builder
            ..write('[Reasoning] ')
            ..writeln(content.text);
        }
      case UriContent():
        builder.writeln(content.uri.toString());
    }
  }
}

final RegExp _fencedJsonRegex = RegExp(
  r'```([a-z]+)?\s*(\{[\s\S]*?\})\s*```',
  caseSensitive: false,
);

/// Extracts the first balanced JSON object found in [messageText].
///
/// Prefers a fenced ```` ```json ```` block; otherwise scans for the first
/// brace-balanced object, respecting strings and escapes.
Map<String, Object?> extractJsonFromText(String messageText) {
  final match = _fencedJsonRegex.firstMatch(messageText);
  if (match != null) {
    return _decodeObject(match.group(2)!);
  }

  final start = messageText.indexOf('{');
  if (start < 0) {
    throw StateError('No JSON object found.');
  }

  var depth = 0;
  var inQuotes = false;
  var inEscape = false;
  int? end;
  for (var i = start; i < messageText.length && end == null; i++) {
    if (inEscape) {
      inEscape = false;
      continue;
    }
    final ch = messageText[i];
    if (ch == '{' && !inQuotes) {
      depth++;
    } else if (ch == '}' && !inQuotes) {
      depth--;
      if (depth == 0) {
        end = i;
      }
    } else if (ch == '"') {
      inQuotes = !inQuotes;
    } else if (ch == r'\') {
      inEscape = true;
    }
  }

  if (end == null) {
    throw StateError('Unbalanced JSON braces.');
  }

  return _decodeObject(messageText.substring(start, end + 1));
}

Map<String, Object?> _decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, Object?>();
  }
  throw StateError('Extracted JSON is not an object.');
}
