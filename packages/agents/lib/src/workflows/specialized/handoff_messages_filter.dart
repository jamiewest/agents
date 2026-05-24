import 'package:extensions/ai.dart';

import '../handoff_tool_call_filtering_behavior.dart';
import '../handoff_workflow_builder.dart';

/// Filters handoff function call messages from history before target handoff.
class HandoffMessagesFilter {
  /// Creates a [HandoffMessagesFilter].
  HandoffMessagesFilter(this.filteringBehavior);

  /// Gets the filtering behavior.
  final HandoffToolCallFilteringBehavior filteringBehavior;

  /// Gets whether [name] is a handoff function name.
  static bool isHandoffFunctionName(String name) =>
      name.startsWith(HandoffWorkflowBuilder.functionPrefix);

  /// Filters [messages].
  Iterable<ChatMessage> filterMessages(Iterable<ChatMessage> messages) {
    if (filteringBehavior == HandoffToolCallFilteringBehavior.none) {
      return messages;
    }

    final filteredCallsWithoutResponses = <String>{};
    final retainedMessages = <ChatMessage>[];
    final filterAllToolCalls =
        filteringBehavior == HandoffToolCallFilteringBehavior.all;

    for (final unfilteredMessage in messages) {
      if (unfilteredMessage.contents.isEmpty) {
        retainedMessages.add(unfilteredMessage);
        continue;
      }

      final retainedContents = <AIContent>[];
      for (final content in unfilteredMessage.contents) {
        if (content is FunctionCallContent &&
            (filterAllToolCalls || isHandoffFunctionName(content.name))) {
          if (!filteredCallsWithoutResponses.add(content.callId)) {
            throw StateError(
              "Duplicate FunctionCallContent with CallId '${content.callId}' "
              'without corresponding FunctionResultContent.',
            );
          }
          continue;
        } else if (content is FunctionResultContent &&
            filteredCallsWithoutResponses.remove(content.callId)) {
          continue;
        }

        retainedContents.add(content);
      }

      if (retainedContents.isEmpty) {
        continue;
      }

      retainedMessages.add(
        ChatMessage(
          role: unfilteredMessage.role,
          contents: retainedContents,
          authorName: unfilteredMessage.authorName,
          createdAt: unfilteredMessage.createdAt,
          messageId: unfilteredMessage.messageId,
          rawRepresentation: unfilteredMessage.rawRepresentation,
          additionalProperties: unfilteredMessage.additionalProperties,
        ),
      );
    }

    return retainedMessages;
  }
}
