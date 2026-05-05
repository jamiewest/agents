import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'agent_response.dart';
import 'agent_response_update.dart';

/// Extension methods for [AgentResponse] and [AgentResponseUpdate].
extension AgentResponseExtensions on AgentResponse {
  /// Returns a [ChatResponse] built from this [AgentResponse].
  ///
  /// If [rawRepresentation] is already a [ChatResponse], that instance is
  /// returned directly; otherwise a shallow copy is constructed.
  ChatResponse asChatResponse() {
    if (rawRepresentation is ChatResponse) {
      return rawRepresentation! as ChatResponse;
    }
    return ChatResponse(
      messages: messages,
      finishReason: finishReason,
      continuationToken: continuationToken,
      additionalProperties: additionalProperties,
    )..rawRepresentation = this;
  }
}

/// Extension methods for [AgentResponseUpdate].
extension AgentResponseUpdateExtensions on AgentResponseUpdate {
  /// Returns a [ChatResponseUpdate] built from this [AgentResponseUpdate].
  ///
  /// If [rawRepresentation] is already a [ChatResponseUpdate], that instance
  /// is returned directly; otherwise a shallow copy is constructed.
  ChatResponseUpdate asChatResponseUpdate() {
    if (rawRepresentation is ChatResponseUpdate) {
      return rawRepresentation! as ChatResponseUpdate;
    }
    return ChatResponseUpdate(
      role: role,
      authorName: authorName,
      contents: contents,
      finishReason: finishReason,
      continuationToken: continuationToken,
      additionalProperties: additionalProperties,
    )..rawRepresentation = this;
  }
}

/// Extension methods for iterables of [AgentResponseUpdate].
extension AgentResponseUpdateIterableExtensions
    on Iterable<AgentResponseUpdate> {
  /// Converts this sequence to a stream of [ChatResponseUpdate] instances.
  Stream<ChatResponseUpdate> asChatResponseUpdates() async* {
    for (final update in this) {
      yield update.asChatResponseUpdate();
    }
  }

  /// Combines this sequence of [AgentResponseUpdate] instances into a single
  /// [AgentResponse].
  AgentResponse toAgentResponse() {
    final updates = map((u) => u.asChatResponseUpdate()).toList();
    final chatResponse = _buildChatResponse(updates);
    return AgentResponse(response: chatResponse);
  }

  static ChatResponse _buildChatResponse(List<ChatResponseUpdate> updates) {
    final messages = <ChatMessage>[];
    ChatMessage? current;
    for (final update in updates) {
      final needsNew = current == null ||
          current.role != (update.role ?? ChatRole.assistant) ||
          current.authorName != update.authorName;
      if (needsNew) {
        current = ChatMessage(
          role: update.role ?? ChatRole.assistant,
          authorName: update.authorName,
          contents: [],
        );
        messages.add(current);
      }
      current!.contents.addAll(update.contents);
    }
    return ChatResponse(
      messages: messages,
      conversationId: updates.lastOrNull?.conversationId,
      finishReason: updates.lastOrNull?.finishReason,
      continuationToken: updates.lastOrNull?.continuationToken,
    );
  }
}

/// Extension methods for streams of [AgentResponseUpdate].
extension AgentResponseUpdateStreamExtensions on Stream<AgentResponseUpdate> {
  /// Combines the stream of [AgentResponseUpdate] instances into a single
  /// [AgentResponse].
  Future<AgentResponse> toAgentResponseAsync({
    CancellationToken? cancellationToken,
  }) async {
    final updates = <AgentResponseUpdate>[];
    await for (final update in this) {
      updates.add(update);
    }
    return updates.toAgentResponse();
  }
}
