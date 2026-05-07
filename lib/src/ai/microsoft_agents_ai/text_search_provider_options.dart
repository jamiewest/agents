import 'package:extensions/ai.dart';

import 'memory/chat_history_memory_provider_options.dart';
import 'text_search_provider.dart';

/// Options controlling the behavior of [TextSearchProvider].
class TextSearchProviderOptions {
  TextSearchProviderOptions();

  /// Gets or sets a value indicating when the search should be executed.
  TextSearchBehavior searchTime = TextSearchBehavior.beforeAIInvoke;

  /// Gets or sets the name of the exposed search tool when operating in
  /// on-demand mode.
  String? functionToolName;

  /// Gets or sets the description of the exposed search tool when operating in
  /// on-demand mode.
  String? functionToolDescription;

  /// Gets or sets the context prompt prefixed to results.
  String? contextPrompt;

  /// Gets or sets the instruction appended after results to request citations.
  String? citationsPrompt;

  /// Optional delegate to fully customize formatting of the result list.
  String Function(List<TextSearchResult>)? contextFormatter;

  /// Gets or sets the number of recent conversation messages to keep in
  /// memory and include when constructing [beforeAIInvoke] search input.
  int recentMessageMemoryLimit = 0;

  /// Gets or sets the key used to store provider state in the state bag.
  String? stateKey;

  /// Gets or sets an optional filter function applied to request messages when
  /// constructing the search input text.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  searchInputMessageFilter;

  /// Gets or sets an optional filter function applied to request messages when
  /// updating recent message memory.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputRequestMessageFilter;

  /// Gets or sets an optional filter function applied to response messages
  /// when updating recent message memory.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputResponseMessageFilter;

  /// Gets or sets the roles included when retaining recent messages.
  List<ChatRole>? recentMessageRolesIncluded;

  /// Gets or sets a value indicating whether sensitive data may appear in
  /// logs.
  bool enableSensitiveTelemetryData = false;

  /// Gets or sets a custom [Redactor] used to redact sensitive data in log
  /// output.
  Redactor? redactor;
}

/// Behavior choices for the provider.
enum TextSearchBehavior {
  /// Execute search prior to each invocation and inject results as a message.
  beforeAIInvoke,

  /// Expose a function tool to perform search on-demand via function calling.
  onDemandFunctionCalling,
}
