import 'package:extensions/ai.dart';

import 'chat_history_memory_provider.dart';

/// Redacts sensitive values before they are written to diagnostic logs.
abstract class Redactor {
  String redact(String? value);
}

class NullRedactor implements Redactor {
  const NullRedactor();

  static const NullRedactor instance = NullRedactor();

  @override
  String redact(String? value) => value ?? '';
}

class ReplacingRedactor implements Redactor {
  const ReplacingRedactor(this.replacement);

  final String replacement;

  @override
  String redact(String? value) => replacement;
}

Redactor replacingRedactor(String replacement) =>
    ReplacingRedactor(replacement);

/// Options controlling the behavior of [ChatHistoryMemoryProvider].
class ChatHistoryMemoryProviderOptions {
  ChatHistoryMemoryProviderOptions();

  /// Gets or sets a value indicating when the search should be executed.
  SearchBehavior searchTime = SearchBehavior.beforeAIInvoke;

  /// Gets or sets the name of the exposed search tool when operating in
  /// on-demand mode.
  String? functionToolName;

  /// Gets or sets the description of the exposed search tool when operating in
  /// on-demand mode.
  String? functionToolDescription;

  /// Gets or sets the context prompt prefixed to results.
  String? contextPrompt;

  /// Gets or sets the maximum number of results to retrieve from the chat
  /// history.
  int? maxResults;

  /// Gets or sets a value indicating whether sensitive data such as user ids
  /// and user messages may appear in logs.
  bool enableSensitiveTelemetryData = false;

  /// Gets or sets a custom [Redactor] used to redact sensitive data in log
  /// output.
  Redactor? redactor;

  /// Gets or sets the key used to store provider state in the state bag.
  String? stateKey;

  /// Gets or sets an optional filter function applied to request messages when
  /// constructing the search text.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  searchInputMessageFilter;

  /// Gets or sets an optional filter function applied to request messages when
  /// storing recent chat history.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputRequestMessageFilter;

  /// Gets or sets an optional filter function applied to response messages when
  /// storing recent chat history.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputResponseMessageFilter;
}

/// Behavior choices for the provider.
enum SearchBehavior {
  /// Execute search prior to each invocation and inject results as a message.
  beforeAIInvoke,

  /// Expose a function tool to perform search on-demand via function calling.
  onDemandFunctionCalling,
}
