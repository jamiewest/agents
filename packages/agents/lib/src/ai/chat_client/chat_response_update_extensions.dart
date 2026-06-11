import 'package:extensions/ai.dart';

/// Combines streamed [ChatResponseUpdate]s into a single [ChatResponse].
///
/// Ports the coalescing behavior of the C#
/// `ChatResponseExtensions.ToChatResponse` helper: contiguous updates with
/// the same role and author are merged into one [ChatMessage], and
/// response-level fields prefer the value from later updates (except
/// `createdAt`, which keeps the first value seen).
extension ChatResponseUpdateListExtensions on List<ChatResponseUpdate> {
  /// Builds a [ChatResponse] from the accumulated updates.
  ChatResponse toChatResponse() {
    final response = ChatResponse();
    ChatMessage? currentMessage;

    for (final update in this) {
      if (_needsNewMessage(currentMessage, update)) {
        currentMessage = ChatMessage(
          role: update.role ?? ChatRole.assistant,
          authorName: update.authorName,
          contents: [],
        );
        currentMessage.messageId = update.messageId;
        currentMessage.createdAt = update.createdAt;
        currentMessage.rawRepresentation = update.rawRepresentation;
        response.messages.add(currentMessage);
      }

      currentMessage!.contents.addAll(update.contents);

      response.responseId = update.responseId ?? response.responseId;
      response.conversationId =
          update.conversationId ?? response.conversationId;
      response.createdAt = response.createdAt ?? update.createdAt;
      response.finishReason = update.finishReason ?? response.finishReason;
      response.modelId = update.modelId ?? response.modelId;
      response.usage = update.usage ?? response.usage;
      response.continuationToken =
          update.continuationToken ?? response.continuationToken;
      response.rawRepresentation =
          update.rawRepresentation ?? response.rawRepresentation;
      response.additionalProperties =
          update.additionalProperties ?? response.additionalProperties;
    }

    return response;
  }

  static bool _needsNewMessage(
    ChatMessage? currentMessage,
    ChatResponseUpdate update,
  ) {
    return currentMessage == null ||
        currentMessage.role != (update.role ?? ChatRole.assistant) ||
        currentMessage.authorName != update.authorName;
  }
}
