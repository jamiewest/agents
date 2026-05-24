import 'package:extensions/ai.dart';

import 'chat_history_memory_provider.dart';

/// Redacts sensitive values before they are written to diagnostic logs.
abstract class Redactor {
  String redact(String? value);
}

/// A [Redactor] that returns the original value unchanged.
///
/// Used when sensitive telemetry data logging is explicitly enabled.
class NullRedactor implements Redactor {
  const NullRedactor();

  static const NullRedactor instance = NullRedactor();

  @override
  String redact(String? value) => value ?? '';
}

/// A [Redactor] that replaces every value with a fixed [replacement] string.
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

  /// When the search should be executed.
  SearchBehavior searchTime = SearchBehavior.beforeAIInvoke;

  /// Name of the exposed search tool when operating in on-demand mode.
  String? functionToolName;

  /// Description of the exposed search tool when operating in on-demand mode.
  String? functionToolDescription;

  /// Context prompt prefixed to results.
  String? contextPrompt;

  /// Maximum number of results to retrieve from the chat history.
  int? maxResults;

  /// Whether sensitive data such as user IDs and user messages may appear in
  /// logs.
  bool enableSensitiveTelemetryData = false;

  /// Custom [Redactor] used to redact sensitive data in log output.
  Redactor? redactor;

  /// Key used to store provider state in the state bag.
  String? stateKey;

  /// Optional filter function applied to request messages when constructing
  /// the search text.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  searchInputMessageFilter;

  /// Optional filter function applied to request messages when storing recent
  /// chat history.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
  storageInputRequestMessageFilter;

  /// Optional filter function applied to response messages when storing recent
  /// chat history.
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
