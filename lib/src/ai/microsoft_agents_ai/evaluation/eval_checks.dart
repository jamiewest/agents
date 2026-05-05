// TODO: import not yet ported
// TODO: import not yet ported
// TODO: import not yet ported
import 'check_result.dart';
import 'eval_check.dart';
import 'eval_item.dart';
import '../../../json_stubs.dart';
import '../../../map_extensions.dart';

/// Built-in check functions for common evaluation patterns.
class EvalChecks {
  EvalChecks();

  /// Creates a check that verifies the response contains all specified
  /// keywords.
  ///
  /// Returns: An [EvalCheck] delegate.
  ///
  /// [keywords] Keywords that must appear in the response.
  static EvalCheck keywordCheck(List<String> keywords, {bool? caseSensitive, }) {
    return keywordCheck(caseSensitive: false, keywords);
  }

  /// Creates a check that verifies specific tools were called in the
  /// conversation. All specified tools must have been called.
  ///
  /// Returns: An [EvalCheck] delegate.
  ///
  /// [toolNames] Tool names that must appear in the conversation.
  static EvalCheck toolCalledCheck(List<String> toolNames, {ToolCalledMode? mode, }) {
    return toolCalledCheck(ToolCalledMode.all, toolNames);
  }

  /// A check that verifies at least one tool was called in the conversation.
  ///
  /// Returns: An [EvalCheck] delegate.
  static EvalCheck toolCallsPresent() {
    return (EvalItem item) =>
        {
            var calledTools = getCalledTools(item);
            var passed = calledTools.length > 0;
            var reason = passed
                ? 'Tools called: ${calledTools.join(", ")}'
                : "No tool calls found in conversation";

            return evalCheckResult(passed, reason, "tool_calls_present");
        };
  }

  /// A check that verifies expected tool calls match on name and optionally
  /// arguments.
  ///
  /// Remarks: For each expected tool call, finds matching calls in the
  /// conversation by name. If [Arguments] is provided, checks that the actual
  /// arguments contain all expected key-value pairs (subset match — extra
  /// actual arguments are OK). If no expected tool calls are set on the item,
  /// the check passes.
  ///
  /// Returns: An [EvalCheck] delegate.
  static EvalCheck toolCallArgsMatch() {
    return (EvalItem item) =>
        {
            var expected = item.expectedToolCalls;
            if (expected == null || expected.length == 0)
            {
                return evalCheckResult(
                  true,
                  "No expected tool calls specified.",
                  "tool_call_args_match",
                );
      }

            var actualCalls = getCalledToolsWithArgs(item);
            int matched = 0;
            var details = List<String>();

            foreach (var exp in expected)
            {
                var matching = actualCalls.where((c) => (c.name == exp.name)).toList();

                if (matching.length == 0)
                {
                    details.add('  ${exp.name}: not called');
                    continue;
        }

                if (exp.arguments == null)
                {
                    matched++;
                    details.add('  ${exp.name}: called (args not checked)');
                    continue;
        }

                // Subset match — all expected keys present with expected values
                bool found = false;
                foreach (var call in matching)
                {
                    if (call.arguments != null
                        && exp.arguments.every((kvp) =>
                            call.arguments.tryGetValue(kvp.key)
                            && equals(actual, kvp.value)))
                    {
                        found = true;
                        break;
          }
        }

                if (found)
                {
                    matched++;
                    details.add('  ${exp.name}: args match');
        }
                else
                {
                    details.add('  ${exp.name}: args mismatch');
        }
      }

            var passed = matched == expected.length;
            var reason = 'Tool call args match: ${matched}/${expected.length}\n${String.join(
              "\n",
              details,
            ) }';
            return evalCheckResult(passed, reason, "tool_call_args_match");
        };
  }

  /// Creates a check that verifies the response is non-empty and meets a
  /// minimum length.
  ///
  /// Returns: An [EvalCheck] delegate.
  ///
  /// [minLength] Minimum response length (default 1).
  static EvalCheck nonEmpty({int? minLength}) {
    return (EvalItem item) =>
        {
            var trimmed = item.response.trim();
            var passed = trimmed.length >= minLength;
            var reason = passed
                ? 'Response length ${trimmed.length} meets minimum ${minLength}'
                : 'Response length ${trimmed.length} is below minimum ${minLength}';

            return evalCheckResult(passed, reason, "non_empty");
        };
  }

  /// Creates a check that verifies the response contains the expected output
  /// text.
  ///
  /// Returns: An [EvalCheck] delegate.
  ///
  /// [caseSensitive] Whether the comparison is case-sensitive (default false).
  static EvalCheck containsExpected({bool? caseSensitive}) {
    return (EvalItem item) =>
        {
            if ((item.expectedOutput == null || item.expectedOutput.isEmpty))
            {
                return evalCheckResult(
                  false,
                  "ExpectedOutput is! set; check cannot be applied.",
                  "contains_expected",
                );
      }

            var comparison = caseSensitive
                ? 
                : ;

            var passed = item.response.contains(item.expectedOutput, comparison);
            var reason = passed
                ? 'Response contains expected output: \"${item.expectedOutput}\"'
                : 'Response does not contain expected output: \"${item.expectedOutput}\"';

            return evalCheckResult(passed, reason, "contains_expected");
        };
  }

  /// A check that verifies the conversation contains at least one image
  /// ([DataContent] or [UriContent] with an image media type).
  ///
  /// Returns: An [EvalCheck] delegate.
  static EvalCheck hasImageContent() {
    return (EvalItem item) =>
        {
            var passed = item.hasImageContent;
            var reason = passed
                ? "Conversation contains image content"
                : "No image content found in conversation";

            return evalCheckResult(passed, reason, "has_image_content");
        };
  }

  static Set<String> getCalledTools(EvalItem item) {
    var calledTools = Set<String>();
    for (final message in item.conversation) {
      for (final content in message.contents) {
        if (content is FunctionCallContent) {
          final functionCall = content as FunctionCallContent;
          calledTools.add(functionCall.name);
        }
      }
    }
    return calledTools;
  }

  static List<stringName, ReadOnlyDictionarystringobjectArguments> getCalledToolsWithArgs(EvalItem item) {
    var calls = List<stringName, ReadOnlyDictionarystringobjectArguments>();
    for (final message in item.conversation) {
      for (final content in message.contents) {
        if (content is FunctionCallContent) {
          final functionCall = content as FunctionCallContent;
          var rawArgs = functionCall.arguments;
          var args = null;
          if (rawArgs != null) {
            var dict = new Dictionary<String, Object>();
            for (final kvp in rawArgs) {
              if (kvp.value != null) {
                // Normalize JsonElement values to their .net equivalents for comparison
                                dict[kvp.key] = kvp.value is JsonElement je ? unwrapJsonElement(je) : kvp.value;
              }
            }
            args = dict;
          }
          calls.add((functionCall.name, args));
        }
      }
    }
    return calls;
  }

  static Object unwrapJsonElement(JsonElement element) {
    return element.valueKind switch
        {
            JsonValueKind.String => element.getString()!,
            JsonValueKind.number => element.tryGetInt64(l) ? l : element.getDouble(),
            JsonValueKind.trueValue => true,
            JsonValueKind.falseValue => false,
            (_) => element.toString(),
        };
  }
}
/// Specifies how [String[])] matches tool names.
enum ToolCalledMode { /// All specified tools must have been called.
all,
/// At least one of the specified tools must have been called.
any }
