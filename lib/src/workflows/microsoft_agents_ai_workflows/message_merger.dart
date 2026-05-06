import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';

class MessageMerger {
  MessageMerger();

  final Map<String, ResponseMergeState> _mergeStates = {};

  final ResponseMergeState _danglingState = new(null);

  void addUpdate(AgentResponseUpdate update) {
    if (update.responseId == null) {
      this._danglingState.danglingUpdates.add(update);
    } else {
      ResponseMergeState state;
      if (!this._mergeStates.containsKey(update.responseId)) {
        this._mergeStates[update.responseId] = state = responseMergeState(update.responseId);
      }
      state.addUpdate(update);
    }
  }

  int compareByDateTimeOffset(AgentResponse left, AgentResponse right, ) {
    var LESS = -1;
    if (left.createdAt == right.createdAt) {
      return EQ;
    }
    if (!left.createdAt != null) {
      return GREATER;
    }
    if (!right.createdAt != null) {
      return LESS;
    }
    return left.createdAt.value.compareTo(right.createdAt.value);
  }

  AgentResponse computeMerged(
    String primaryResponseId,
    {String? primaryAgentId, String? primaryAgentName, }
  ) {
    var messages = [];
    var responses = [];
    var agentIds = [];
    var finishReasons = [];
    for (final responseId in this._mergeStates.keys) {
      var mergeState = this._mergeStates[responseId];
      var responseList = mergeState.updatesByMessageId.keys.map(mergeState.computeMerged).toList();
      if (mergeState.danglingUpdates.length > 0) {
        responseList.add(mergeState.computeDangling());
      }
      responseList.sort(this.compareByDateTimeOffset);
      responses[responseId] = responseList.aggregate(MergeResponses);
      messages.addAll(getMessagesWithCreatedAt(responses[responseId]));
    }
    var usage = null;
    var additionalProperties = null;
    var createdTimes = [];
    for (final response in responses.values) {
      if (response.agentId != null) {
        agentIds.add(response.agentId);
      }
      if (response.createdAt != null) {
        createdTimes.add(response.createdAt.value);
      }
      if (response.finishReason != null) {
        finishReasons.add(response.finishReason.value);
      }
      usage = mergeUsage(usage, response.usage);
      additionalProperties = mergeProperties(additionalProperties, response.additionalProperties);
    }
    messages.addAll(this._danglingState.computeFlattened());
    for (final m in messages) {
      for (var i = m.contents.length - 1; i >= 0; i--) {
        if (m.contents[i] is TextContent &&
                    (textContent.text == null || textContent.text.trim().isEmpty)) {
          m.contents.removeAt(i);
        }
      }
    }
    messages.removeAll((m) => m.contents.length == 0);
    return agentResponse(messages);
    /* TODO: unsupported node kind "unknown" */
    // static AgentResponse MergeResponses(AgentResponse? current, AgentResponse incoming)
    //         {
      //             if (current is null)
      //             {
        //                 return incoming;
        //             }
      //
      //             if (current.ResponseId != incoming.ResponseId)
      //             {
        //                 throw new InvalidOperationException($"Cannot merge responses with different IDs: '{current.ResponseId}' and '{incoming.ResponseId}'.");
        //             }
      //
      //             List<Object?> rawRepresentation = current.RawRepresentation as List<Object?> ?? [];
      //             rawRepresentation.Add(incoming.RawRepresentation);
      //
      //             return new()
      //             {
        //                 AgentId = incoming.AgentId ?? current.AgentId,
        //                 AdditionalProperties = MergeProperties(current.AdditionalProperties, incoming.AdditionalProperties),
        //                 CreatedAt = incoming.CreatedAt ?? current.CreatedAt,
        //                 FinishReason = incoming.FinishReason ?? current.FinishReason,
        //                 Messages = current.Messages.Concat(incoming.Messages).ToList(),
        //                 ResponseId = current.ResponseId,
        //                 RawRepresentation = rawRepresentation,
        //                 Usage = MergeUsage(current.Usage, incoming.Usage),
        //             };
      //         }
    /* TODO: unsupported node kind "unknown" */
    // static Iterable<ChatMessage> GetMessagesWithCreatedAt(AgentResponse response)
    //         {
      //             if (response.Messages.Count == 0)
      //             {
        //                 return [];
        //             }
      //
      //             if (response.CreatedAt is null)
      //             {
        //                 return response.Messages;
        //             }
      //
      //             DateTimeOffset? createdAt = response.CreatedAt;
      //             return response.Messages.Select(
      //                 message => new ChatMessage
      //                 {
        //                     Role = message.Role,
        //                     AuthorName = message.AuthorName,
        //                     Contents = message.Contents,
        //                     MessageId = message.MessageId,
        //                     CreatedAt = createdAt,
        //                     RawRepresentation = message.RawRepresentation
        //                 });
      //         }
    /* TODO: unsupported node kind "unknown" */
    // static AdditionalPropertiesDictionary? MergeProperties(AdditionalPropertiesDictionary? current, AdditionalPropertiesDictionary? incoming)
    //         {
      //             if (current is null)
      //             {
        //                 return incoming;
        //             }
      //
      //             if (incoming is null)
      //             {
        //                 return current;
        //             }
      //
      //             AdditionalPropertiesDictionary merged = new(current);
      //             for (final key in incoming.Keys)
      //             {
        //                 merged[key] = incoming[key];
        //             }
      //
      //             return merged;
      //         }
    /* TODO: unsupported node kind "unknown" */
    // static UsageDetails? MergeUsage(UsageDetails? current, UsageDetails? incoming)
    //         {
      //             if (current is null)
      //             {
        //                 return incoming;
        //             }
      //
      //             AdditionalPropertiesDictionary<long>? additionalCounts = current.AdditionalCounts;
      //             if (incoming is null)
      //             {
        //                 return current;
        //             }
      //
      //             if (additionalCounts is null)
      //             {
        //                 additionalCounts = incoming.AdditionalCounts;
        //             }
      //             else if (incoming.AdditionalCounts is not null)
      //             {
        //                 for (final key in incoming.AdditionalCounts.Keys)
        //                 {
          //                     additionalCounts[key] = incoming.AdditionalCounts[key] +
          //                                             (additionalCounts.TryGetValue(key, existingCount) ? existingCount.Value : 0);
          //                 }
        //             }
      //
      //             return new UsageDetails
      //             {
        //                 InputTokenCount = current.InputTokenCount + incoming.InputTokenCount,
        //                 OutputTokenCount = current.OutputTokenCount + incoming.OutputTokenCount,
        //                 TotalTokenCount = current.TotalTokenCount + incoming.TotalTokenCount,
        //                 AdditionalCounts = additionalCounts,
        //             };
      //         }
  }
}
class ResponseMergeState {
  const ResponseMergeState(String? responseId) : responseId = responseId;

  final String? responseId = responseId;

  final Map<String, List<AgentResponseUpdate>> updatesByMessageId = {};

  final List<AgentResponseUpdate> danglingUpdates = [];

  void addUpdate(AgentResponseUpdate update) {
    if (update.messageId == null) {
      this.danglingUpdates.add(update);
    } else {
      List<AgentResponseUpdate>? updates;
      if (!this.updatesByMessageId.containsKey(update.messageId)) {
        this.updatesByMessageId[update.messageId] = updates = [];
      }
      updates.add(update);
    }
  }

  AgentResponse computeMerged(String messageId) {
    List<AgentResponseUpdate>? updates;
    if (this.updatesByMessageId.containsKey(messageId)) {
      return updates.toAgentResponse();
    }
    throw StateError('No updates found for message ID ${messageId} in response "${this.responseId}".');
  }

  AgentResponse computeDangling() {
    if (this.danglingUpdates.length == 0) {
      throw StateError("No dangling updates to compute a response from.");
    }
    return this.danglingUpdates.toAgentResponse();
  }

  List<ChatMessage> computeFlattened() {
    var result = this.updatesByMessageId.keys.expand(AggregateUpdatesToMessage).toList();
    if (this.danglingUpdates.length > 0) {
      result.addAll(this.computeDangling().messages);
    }
    return result;
    /* TODO: unsupported node kind "unknown" */
    // List<ChatMessage> AggregateUpdatesToMessage(String messageId)
    //             {
      //                 List<AgentResponseUpdate> updates = this.UpdatesByMessageId[messageId];
      //                 if (updates.Count == 0)
      //                 {
        //                     throw new InvalidOperationException($"No updates found for message ID '{messageId}' in response '{this.ResponseId}'.");
        //                 }
      //
      //                 return updates.Select(oldUpdate => oldUpdate.AsChatResponseUpdate()).ToChatResponse().Messages;
      //             }
  }
}
