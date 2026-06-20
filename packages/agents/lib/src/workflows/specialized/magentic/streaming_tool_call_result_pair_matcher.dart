import 'package:extensions/ai.dart';

/// The kind of tool call tracked by [StreamingToolCallResultPairMatcher].
enum ToolCallType {
  /// A regular function call.
  function,

  /// An MCP server tool call.
  mcpServerTool,
}

/// A summary of a collected, as-yet-unmatched tool call.
class ToolCallSummary {
  /// Creates a [ToolCallSummary].
  const ToolCallSummary(this.callType, this.callId, this.name);

  /// Gets the kind of call.
  final ToolCallType callType;

  /// Gets the call identifier.
  final String callId;

  /// Gets the tool/function name.
  final String name;
}

/// Matches tool call content with its corresponding result content by call id.
///
/// Used while rendering streamed chat content to text so that result blocks
/// can be labelled with the originating tool's name.
class StreamingToolCallResultPairMatcher {
  final Map<_CallSummaryKey, ToolCallSummary> _callSummaries =
      <_CallSummaryKey, ToolCallSummary>{};

  /// Whether any collected calls have not yet been resolved by a result.
  bool get hasUnmatchedCalls => _callSummaries.isNotEmpty;

  /// Gets the collected calls that have not yet been resolved by a result.
  Iterable<ToolCallSummary> get unmatchedCalls =>
      hasUnmatchedCalls ? _callSummaries.values.toList() : const [];

  void _collect(
    ToolCallType callType,
    String callId,
    String name,
    String callContentTypeName,
    String resultContentTypeName,
  ) {
    final key = _CallSummaryKey(callType, callId);
    if (_callSummaries.containsKey(key)) {
      throw StateError(
        "Duplicate $callContentTypeName with CallId '$callId' without "
        'corresponding $resultContentTypeName.',
      );
    }
    _callSummaries[key] = ToolCallSummary(callType, callId, name);
  }

  /// Records a function call so its later result can be matched.
  void collectFunctionCall(FunctionCallContent callContent) => _collect(
    ToolCallType.function,
    callContent.callId,
    callContent.name,
    'FunctionCallContent',
    'FunctionResultContent',
  );

  /// Records an MCP server tool call so its later result can be matched.
  void collectMcpServerToolCall(McpServerToolCallContent callContent) =>
      _collect(
        ToolCallType.mcpServerTool,
        callContent.callId,
        callContent.toolName,
        'McpServerToolCallContent',
        'McpServerToolResultContent',
      );

  String? _resolve(ToolCallType callType, String callId) {
    final summary = _callSummaries.remove(_CallSummaryKey(callType, callId));
    return summary?.name;
  }

  /// Resolves the name for a function result, or `null` if unmatched.
  String? resolveFunctionCall(FunctionResultContent resultContent) =>
      _resolve(ToolCallType.function, resultContent.callId);

  /// Resolves the name for an MCP server tool result, or `null` if unmatched.
  String? resolveMcpServerToolCall(MCPServerToolResultContent resultContent) =>
      _resolve(ToolCallType.mcpServerTool, resultContent.callId);
}

class _CallSummaryKey {
  const _CallSummaryKey(this.type, this.callId);

  final ToolCallType type;
  final String callId;

  @override
  bool operator ==(Object other) =>
      other is _CallSummaryKey && other.type == type && other.callId == callId;

  @override
  int get hashCode => Object.hash(type, callId);
}
