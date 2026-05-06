import 'package:extensions/ai.dart';
import '../../../func_typedefs.dart';
import 'chat_history_memory_provider.dart';

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
  ///
  /// Remarks: When set to `true`, sensitive data is passed through to logs
  /// unchanged and any configured [Redactor] is ignored. This property takes
  /// precedence over [Redactor].
  bool enableSensitiveTelemetryData = false;

  /// Gets or sets a custom [Redactor] used to redact sensitive data in log
  /// output.
  Object? redactor;

  /// Gets or sets the key used to store provider state in the [StateBag].
  String? stateKey;

  /// Gets or sets an optional filter function applied to request messages when
  /// constructing the search text to use to search for relevant chat history
  /// during [CancellationToken)].
  Func<Iterable<ChatMessage>, Iterable<ChatMessage>>? searchInputMessageFilter;

  /// Gets or sets an optional filter function applied to request messages when
  /// storing recent chat history during [CancellationToken)].
  Func<Iterable<ChatMessage>, Iterable<ChatMessage>>?
  storageInputRequestMessageFilter;

  /// Gets or sets an optional filter function applied to response messages when
  /// storing recent chat history during [CancellationToken)].
  Func<Iterable<ChatMessage>, Iterable<ChatMessage>>?
  storageInputResponseMessageFilter;
}

/// Behavior choices for the provider.
enum SearchBehavior {
  /// Execute search prior to each invocation and inject results as a message.
  beforeAIInvoke,

  /// Expose a function tool to perform search on-demand via function/tool
  /// calling.
  onDemandFunctionCalling,
}
