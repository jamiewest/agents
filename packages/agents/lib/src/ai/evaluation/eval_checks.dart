import 'dart:convert';

import 'package:extensions/ai.dart';

import '../../json_stubs.dart';
import 'check_result.dart';
import 'eval_check.dart';
import 'eval_item.dart';

/// Built-in check functions for common evaluation patterns.
class EvalChecks {
  EvalChecks._();

  /// Creates a check that verifies the response contains all specified
  /// keywords.
  static EvalCheck keywordCheck(
    List<String> keywords, {
    bool caseSensitive = false,
  }) {
    return (EvalItem item) {
      final response = caseSensitive
          ? item.response
          : item.response.toLowerCase();
      final missing = keywords
          .where(
            (keyword) => !response.contains(
              caseSensitive ? keyword : keyword.toLowerCase(),
            ),
          )
          .toList();
      final passed = missing.isEmpty;
      final reason = passed
          ? 'Response contains all keywords: ${keywords.join(", ")}'
          : 'Response missing keywords: ${missing.join(", ")}';
      return EvalCheckResult(passed, reason, 'keyword_check');
    };
  }

  /// Creates a check that verifies specific tools were called in the
  /// conversation.
  static EvalCheck toolCalledCheck(
    List<String> toolNames, {
    ToolCalledMode mode = ToolCalledMode.all,
  }) {
    return (EvalItem item) {
      final calledTools = getCalledTools(item);
      final matched = toolNames.where(calledTools.contains).toList();
      final passed = mode == ToolCalledMode.all
          ? matched.length == toolNames.length
          : matched.isNotEmpty;
      final reason = passed
          ? 'Tools called: ${matched.join(", ")}'
          : 'Expected ${mode == ToolCalledMode.all ? "all" : "any"} tools: ${toolNames.join(", ")}; called: ${calledTools.join(", ")}';
      return EvalCheckResult(passed, reason, 'tool_called');
    };
  }

  /// A check that verifies at least one tool was called in the conversation.
  static EvalCheck toolCallsPresent() {
    return (EvalItem item) {
      final calledTools = getCalledTools(item);
      final passed = calledTools.isNotEmpty;
      final reason = passed
          ? 'Tools called: ${calledTools.join(", ")}'
          : 'No tool calls found in conversation';
      return EvalCheckResult(passed, reason, 'tool_calls_present');
    };
  }

  /// A check that verifies expected tool calls match on name and optionally
  /// arguments.
  static EvalCheck toolCallArgsMatch() {
    return (EvalItem item) {
      final expected = item.expectedToolCalls;
      if (expected == null || expected.isEmpty) {
        return const EvalCheckResult(
          true,
          'No expected tool calls specified.',
          'tool_call_args_match',
        );
      }

      final actualCalls = getCalledToolsWithArgs(item);
      var matched = 0;
      final details = <String>[];

      for (final exp in expected) {
        final matching = actualCalls
            .where((call) => call.name == exp.name)
            .toList();
        if (matching.isEmpty) {
          details.add('  ${exp.name}: not called');
          continue;
        }

        final expectedArguments = exp.arguments;
        if (expectedArguments == null) {
          matched++;
          details.add('  ${exp.name}: called (args not checked)');
          continue;
        }

        final found = matching.any(
          (call) => _argumentsContain(call.arguments, expectedArguments),
        );
        if (found) {
          matched++;
          details.add('  ${exp.name}: args match');
        } else {
          details.add('  ${exp.name}: args mismatch');
        }
      }

      final passed = matched == expected.length;
      final reason =
          'Tool call args match: $matched/${expected.length}\n${details.join("\n")}';
      return EvalCheckResult(passed, reason, 'tool_call_args_match');
    };
  }

  /// Creates a check that verifies the response is non-empty and meets a
  /// minimum length.
  static EvalCheck nonEmpty({int minLength = 1}) {
    return (EvalItem item) {
      final trimmed = item.response.trim();
      final passed = trimmed.length >= minLength;
      final reason = passed
          ? 'Response length ${trimmed.length} meets minimum $minLength'
          : 'Response length ${trimmed.length} is below minimum $minLength';
      return EvalCheckResult(passed, reason, 'non_empty');
    };
  }

  /// Creates a check that verifies the response contains the expected output
  /// text.
  static EvalCheck containsExpected({bool caseSensitive = false}) {
    return (EvalItem item) {
      final expectedOutput = item.expectedOutput;
      if (expectedOutput == null || expectedOutput.isEmpty) {
        return const EvalCheckResult(
          false,
          'ExpectedOutput is not set; check cannot be applied.',
          'contains_expected',
        );
      }

      final haystack = caseSensitive
          ? item.response
          : item.response.toLowerCase();
      final needle = caseSensitive
          ? expectedOutput
          : expectedOutput.toLowerCase();
      final passed = haystack.contains(needle);
      final reason = passed
          ? 'Response contains expected output: "$expectedOutput"'
          : 'Response does not contain expected output: "$expectedOutput"';
      return EvalCheckResult(passed, reason, 'contains_expected');
    };
  }

  /// A check that verifies the conversation contains at least one image.
  static EvalCheck hasImageContent() {
    return (EvalItem item) {
      final passed = item.hasImageContent;
      final reason = passed
          ? 'Conversation contains image content'
          : 'No image content found in conversation';
      return EvalCheckResult(passed, reason, 'has_image_content');
    };
  }

  static Set<String> getCalledTools(EvalItem item) {
    final calledTools = <String>{};
    for (final message in item.conversation) {
      for (final content in message.contents) {
        if (content is FunctionCallContent) {
          calledTools.add(content.name);
        }
      }
    }
    return calledTools;
  }

  static List<({String name, Map<String, Object?>? arguments})>
  getCalledToolsWithArgs(EvalItem item) {
    final calls = <({String name, Map<String, Object?>? arguments})>[];
    for (final message in item.conversation) {
      for (final content in message.contents) {
        if (content is FunctionCallContent) {
          final rawArgs = content.arguments;
          final args = rawArgs == null
              ? null
              : {
                  for (final entry in rawArgs.entries)
                    if (entry.value != null)
                      entry.key: entry.value is JsonElement
                          ? unwrapJsonElement(entry.value! as JsonElement)
                          : entry.value,
                };
          calls.add((name: content.name, arguments: args));
        }
      }
    }
    return calls;
  }

  static Object? unwrapJsonElement(JsonElement element) => element.value;

  static bool _argumentsContain(
    Map<String, Object?>? actual,
    Map<String, Object?> expected,
  ) {
    if (actual == null) {
      return false;
    }
    for (final entry in expected.entries) {
      if (!actual.containsKey(entry.key) ||
          !_valueEquals(actual[entry.key], entry.value)) {
        return false;
      }
    }
    return true;
  }

  static bool _valueEquals(Object? left, Object? right) {
    final normalizedLeft = left is JsonElement ? left.value : left;
    final normalizedRight = right is JsonElement ? right.value : right;
    if (normalizedLeft is Map || normalizedLeft is List) {
      return jsonEncode(normalizedLeft) == jsonEncode(normalizedRight);
    }
    if (normalizedRight is Map || normalizedRight is List) {
      return jsonEncode(normalizedLeft) == jsonEncode(normalizedRight);
    }
    return normalizedLeft == normalizedRight;
  }
}

/// Specifies how a tool-name list matches called tools.
enum ToolCalledMode {
  /// All specified tools must have been called.
  all,

  /// At least one of the specified tools must have been called.
  any,
}
