import 'package:extensions/ai.dart';
import '../handoff_tool_call_filtering_behavior.dart';
import '../handoff_workflow_builder.dart';

class HandoffMessagesFilter {
  HandoffMessagesFilter(HandoffToolCallFilteringBehavior filteringBehavior) : _filteringBehavior = filteringBehavior {
  }

  final HandoffToolCallFilteringBehavior _filteringBehavior;

  static bool isHandoffFunctionName(String name) {
    return name.startsWith(HandoffWorkflowBuilder.functionPrefix);
  }

  Iterable<ChatMessage> filterMessages(Iterable<ChatMessage> messages) {
    if (this._filteringBehavior == HandoffToolCallFilteringBehavior.none) {
      return messages;
    }
    var filteredCallsWithoutResponses = new();
    var retainedMessages = [];
    var filterAllToolCalls = this._filteringBehavior == HandoffToolCallFilteringBehavior.all;
    for (final unfilteredMessage in messages) {
      if (unfilteredMessage.contents == null || unfilteredMessage.contents.length == 0) {
        retainedMessages.add(unfilteredMessage);
        continue;
      }
      var retainedContents = new(capacity: unfilteredMessage.contents.length);
      for (final content in unfilteredMessage.contents) {
        if (content is FunctionCallContent
                    && (filterAllToolCalls || isHandoffFunctionName(fcc.name))) {
          if (!filteredCallsWithoutResponses.add(fcc.callId)) {
            throw StateError("Duplicate FunctionCallContent with CallId ${fcc.callId} without corresponding FunctionResultContent.");
          }
          continue;
        } else if (content is FunctionResultContent) {
          final frc = content as FunctionResultContent;
          if (filteredCallsWithoutResponses.remove(frc.callId)) {
            continue;
          }
        }
        // FCC/FRC, but not filtered, or neither FCC nor FRC: this should not be filtered retainedContents.add(content);
      }
      if (retainedContents.length == 0) {
        continue;
      }
      var filteredMessage = unfilteredMessage.clone();
      filteredMessage.contents = retainedContents;
      retainedMessages.add(filteredMessage);
    }
    return retainedMessages;
  }
}
