import 'package:extensions/ai.dart';

import 'conversation_splitter.dart';
import 'expected_tool_call.dart';

/// Provider-agnostic data for a single evaluation item.
class EvalItem {
  EvalItem({
    this.query = '',
    this.response = '',
    List<ChatMessage>? conversation,
    this.splitter,
  }) : conversation = conversation ?? [];

  /// Gets the user query.
  String query;

  /// Gets the agent response text.
  String response;

  /// Gets the full conversation history.
  List<ChatMessage> conversation;

  /// Tools available to the agent.
  List<AITool>? tools;

  /// Grounding context for evaluation.
  String? context;

  /// Expected output for ground-truth comparison.
  String? expectedOutput;

  /// Expected tool calls for tool-correctness evaluation.
  List<ExpectedToolCall>? expectedToolCalls;

  /// Raw chat response for MEAI evaluators.
  ChatResponse? rawResponse;

  /// Conversation splitter for this item.
  ConversationSplitter? splitter;

  /// Gets whether any message in the conversation contains image content.
  bool get hasImageContent {
    return conversation.any(
      (message) => message.contents.any(
        (content) =>
            (content is DataContent && content.hasTopLevelMediaType('image')) ||
            (content is UriContent && content.hasTopLevelMediaType('image')),
      ),
    );
  }

  /// Splits the conversation into query messages and response messages.
  (List<ChatMessage>, List<ChatMessage>) split({
    ConversationSplitter? splitter,
  }) {
    final effective =
        splitter ?? this.splitter ?? ConversationSplitters.lastTurn;
    return effective.split(conversation);
  }

  /// Splits a multi-turn conversation into one [EvalItem] per user turn.
  static List<EvalItem> perTurnItems(
    List<ChatMessage> conversation, {
    List<AITool>? tools,
    String? context,
  }) {
    final items = <EvalItem>[];
    final userIndices = <int>[];
    for (var i = 0; i < conversation.length; i++) {
      if (conversation[i].role == ChatRole.user) {
        userIndices.add(i);
      }
    }

    for (var t = 0; t < userIndices.length; t++) {
      final userIdx = userIndices[t];
      final nextBoundary = t + 1 < userIndices.length
          ? userIndices[t + 1]
          : conversation.length;
      final responseMessages = conversation
          .skip(userIdx + 1)
          .take(nextBoundary - userIdx - 1)
          .toList();
      final responseText = responseMessages
          .where(
            (message) =>
                message.role == ChatRole.assistant &&
                message.text.trim().isNotEmpty,
          )
          .map((message) => message.text)
          .join(' ');
      items.add(
        EvalItem(
            query: conversation[userIdx].text,
            response: responseText,
            conversation: conversation.take(nextBoundary).toList(),
          )
          ..tools = tools
          ..context = context,
      );
    }
    return items;
  }
}
