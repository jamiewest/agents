import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import 'text_search_provider.dart';

/// Options controlling the behavior of [TextSearchProvider].
class TextSearchProviderOptions {
  TextSearchProviderOptions();

  /// Gets or sets a value indicating when the search should be executed.
  TextSearchBehavior searchTime = TextSearchBehavior.BeforeAIInvoke;

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
  ///
  /// Remarks: If provided, [ContextPrompt] and [CitationsPrompt] are ignored.
  Func<List<TextSearchResult>, String>? contextFormatter;

  /// Gets or sets the number of recent conversation messages (both user and
  /// assistant) to keep in memory and include when constructing the search
  /// input for [BeforeAIInvoke] searches.
  int recentMessageMemoryLimit;

  /// Gets or sets the key used to store provider state in the [StateBag].
  String? stateKey;

  /// Gets or sets an optional filter function applied to request messages when
  /// constructing the search input text during [CancellationToken)].
  Func<Iterable<ChatMessage>, Iterable<ChatMessage>>? searchInputMessageFilter;

  /// Gets or sets an optional filter function applied to request messages when
  /// updating the recent message memory during [CancellationToken)].
  Func<Iterable<ChatMessage>, Iterable<ChatMessage>>?
  storageInputRequestMessageFilter;

  /// Gets or sets an optional filter function applied to response messages when
  /// updating the recent message memory during [CancellationToken)].
  Func<Iterable<ChatMessage>, Iterable<ChatMessage>>?
  storageInputResponseMessageFilter;

  /// Gets or sets the list of [ChatRole] types to filter recent messages to
  /// when deciding which recent messages to include when constructing the
  /// search input.
  ///
  /// Remarks: Depending on your scenario, you may want to use only user
  /// messages, only assistant messages, or both. For example, if the assistant
  /// may often provide clarifying questions or if the conversation is expected
  /// to be particularly chatty, you may want to include assistant messages in
  /// the search context as well. Be careful when including assistant messages
  /// though, as they may skew the search results towards information that has
  /// already been provided by the assistant, rather than focusing on the user's
  /// current needs.
  List<ChatRole>? recentMessageRolesIncluded;

  /// Gets or sets a value indicating whether sensitive data such as user
  /// queries and search results may appear in logs.
  ///
  /// Remarks: When set to `true`, sensitive data is passed through to logs
  /// unchanged and any configured [Redactor] is ignored. This property takes
  /// precedence over [Redactor].
  bool enableSensitiveTelemetryData;

  /// Gets or sets a custom [Redactor] used to redact sensitive data in log
  /// output.
  Redactor? redactor;
}

/// Behavior choices for the provider.
enum TextSearchBehavior {
  /// Execute search prior to each invocation and inject results as a message.
  beforeAIInvoke,

  /// Expose a function tool to perform search on-demand via function/tool
  /// calling.
  onDemandFunctionCalling,
}
