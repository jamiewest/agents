import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

import 'a2a_artifact_extensions.dart';
import 'agent_task_status_extensions.dart';

/// Extension methods for [A2ATask].
extension A2AAgentTaskExtensions on A2ATask {
  /// Converts this task to a list of [ChatMessage] objects.
  ///
  /// Returns messages built from artifacts and any pending user-input request
  /// attached to the task status. Returns `null` when there is nothing to
  /// surface.
  List<ChatMessage>? toChatMessages() {
    List<ChatMessage>? messages;

    final artifactList = artifacts;
    if (artifactList != null && artifactList.isNotEmpty) {
      for (final artifact in artifactList) {
        (messages ??= []).add(artifact.toChatMessage());
      }
    }

    final userInputRequests = status?.getUserInputRequests();
    if (userInputRequests != null) {
      (messages ??= []).add(
        ChatMessage(role: ChatRole.assistant, contents: userInputRequests)
          ..rawRepresentation = status,
      );
    }

    return messages;
  }

  /// Converts this task to a flat list of [AIContent] objects.
  List<AIContent> toAIContents() {
    final result = <AIContent>[];

    final artifactList = artifacts;
    if (artifactList != null) {
      for (final artifact in artifactList) {
        result.addAll(artifact.toAIContents());
      }
    }

    final userInputRequests = status?.getUserInputRequests();
    if (userInputRequests != null) {
      result.addAll(userInputRequests);
    }

    return result;
  }
}
