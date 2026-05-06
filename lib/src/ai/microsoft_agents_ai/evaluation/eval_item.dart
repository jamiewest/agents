import 'package:extensions/ai.dart';
import 'conversation_splitter.dart';
import 'eval_check.dart';
import 'expected_tool_call.dart';

/// Provider-agnostic data for a single evaluation item.
class EvalItem {
  /// Initializes a new instance of the [EvalItem] class.
  ///
  /// [query] The user query.
  ///
  /// [response] The agent response text.
  ///
  /// [conversation] The full conversation as [ChatMessage] list.
  EvalItem({String? query = null, String? response = null, List<ChatMessage>? conversation = null, ConversationSplitter? splitter = null, }) {
    this.query = query;
    this.response = response;
    this.conversation = conversation;
  }

  /// Gets the user query.
  late final String query;

  /// Gets the agent response text.
  late final String response;

  /// Gets the full conversation history.
  ///
  /// Remarks: The conversation preserves all content types including images
  /// ([DataContent], [UriContent] with image media types). Use this property in
  /// custom [EvalCheck] functions to inspect multimodal content that isn't
  /// captured in the text-only [Query] and [Response] properties.
  late final List<ChatMessage> conversation;

  /// Gets or sets the tools available to the agent.
  List<AITool>? tools;

  /// Gets or sets grounding context for evaluation.
  String? context;

  /// Gets or sets the expected output for ground-truth comparison.
  String? expectedOutput;

  /// Gets or sets the expected tool calls for tool-correctness evaluation.
  ///
  /// Remarks: Each entry describes a tool call the agent should make. The
  /// evaluator decides matching semantics (ordering, extras, argument
  /// checking). See [ExpectedToolCall].
  List<ExpectedToolCall>? expectedToolCalls;

  /// Gets or sets the raw chat response for MEAI evaluators.
  ChatResponse? rawResponse;

  /// Gets or sets the conversation splitter for this item.
  ///
  /// Remarks: When set by orchestration functions (e.g.
  /// `EvaluateAsync(splitter: ...)`), this is used as the default by
  /// [ConversationSplitter)]. Priority: explicit `Split(splitter)` argument
  /// &gt; [Splitter] &gt; [LastTurn].
  ConversationSplitter? splitter;

  /// Gets whether any message in the conversation contains image content.
  ///
  /// Remarks: Checks for [DataContent] or [UriContent] with an image media
  /// type. Useful in [EvalCheck] functions to verify multimodal content is
  /// present.
  bool get hasImageContent {
    return this.conversation.any((m) =>
            m.contents.any((c) =>
                (c is DataContent && dc.hasTopLevelMediaType("image"))
                || (c is UriContent && uc.hasTopLevelMediaType("image"))));
  }

  /// Splits the conversation into query messages and response messages.
  ///
  /// Returns: A tuple of (query messages, response messages).
  ///
  /// [splitter] The splitter to use. When `null`, uses [Splitter] if set,
  /// otherwise [LastTurn].
  (List<ChatMessage>, List<ChatMessage>) split({ConversationSplitter? splitter}) {
    var effective = splitter ?? this.splitter ?? ConversationSplitters.lastTurn;
    return effective.split(this.conversation);
  }

  /// Splits a multi-turn conversation into one [EvalItem] per user turn.
  ///
  /// Remarks: Each user message starts a new turn. The resulting item has
  /// cumulative context: query messages contain the full conversation up to and
  /// including that user message, and the response is everything up to the next
  /// user message.
  ///
  /// Returns: A list of eval items, one per user turn.
  ///
  /// [conversation] The full conversation to split.
  ///
  /// [tools] Optional tools available to the agent.
  ///
  /// [context] Optional grounding context.
  static List<EvalItem> perTurnItems(
    List<ChatMessage> conversation,
    {List<AITool>? tools, String? context, }
  ) {
    var items = List<EvalItem>();
    var userIndices = List<int>();
    for (var i = 0; i < conversation.length; i++) {
      if (conversation[i].role == ChatRole.user) {
        userIndices.add(i);
      }
    }
    for (var t = 0; t < userIndices.length; t++) {
      var userIdx = userIndices[t];
      var nextBoundary = t + 1 < userIndices.length
                ? userIndices[t + 1]
                : conversation.length;
      var responseMessages = conversation.skip(userIdx + 1).take(nextBoundary - userIdx - 1).toList();
      var query = conversation[userIdx].text ?? '';
      var responseText = String.join(
                " ",
                responseMessages
                    .where((m) => m.role == ChatRole.assistant && !(m.text == null || m.text.isEmpty))
                    .map((m) => m.text));
      var fullSlice = conversation.take(nextBoundary).toList();
      var item = evalItem(query, responseText, fullSlice);
      items.add(item);
    }
    return items;
  }
}
