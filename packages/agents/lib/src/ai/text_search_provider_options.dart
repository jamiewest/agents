import 'package:extensions/ai.dart';

import 'memory/chat_history_memory_provider_options.dart';
import 'text_search_provider.dart';

/// Options controlling the behavior of [TextSearchProvider].
class TextSearchProviderOptions {
  TextSearchProviderOptions();

  /// When the search should be executed.
  TextSearchBehavior searchTime = TextSearchBehavior.beforeAIInvoke;

  /// Name of the exposed search tool when operating in on-demand mode.
  String? functionToolName;

  /// Description of the exposed search tool when operating in on-demand mode.
  String? functionToolDescription;

  /// Context prompt prefixed to results.
  String? contextPrompt;

  /// Instruction appended after results to request citations.
  String? citationsPrompt;

  /// Optional delegate to fully customize formatting of the result list.
  String Function(List<TextSearchResult>)? contextFormatter;

  /// Number of recent conversation messages to keep in memory and include when
  /// constructing `beforeAIInvoke` search input.
  int recentMessageMemoryLimit = 0;

  /// Key used to store provider state in the state bag.
  String? stateKey;

  /// Optional filter function applied to request messages when constructing
  /// the search input text.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  searchInputMessageFilter;

  /// Optional filter function applied to request messages when updating recent
  /// message memory.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputRequestMessageFilter;

  /// Optional filter function applied to response messages when updating
  /// recent message memory.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputResponseMessageFilter;

  /// Roles included when retaining recent messages.
  List<ChatRole>? recentMessageRolesIncluded;

  /// Whether sensitive data may appear in logs.
  bool enableSensitiveTelemetryData = false;

  /// Custom [Redactor] used to redact sensitive data in log output.
  Redactor? redactor;
}

/// Behavior choices for the provider.
enum TextSearchBehavior {
  /// Execute search prior to each invocation and inject results as a message.
  beforeAIInvoke,

  /// Expose a function tool to perform search on-demand via function calling.
  onDemandFunctionCalling,
}
