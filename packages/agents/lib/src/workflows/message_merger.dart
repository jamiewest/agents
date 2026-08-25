import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_extensions.dart';
import '../abstractions/agent_response_update.dart';
import '../shared/usage_aggregator.dart';

/// Merges streams of [AgentResponseUpdate]s grouped by response and message
/// identifiers into coherent [AgentResponse] objects.
class MessageMerger {
  final Map<String, _ResponseMergeState> _mergeStates = {};
  final _ResponseMergeState _danglingState = _ResponseMergeState(null);

  /// Adds [update] to the merge state keyed by its [AgentResponseUpdate.responseId].
  ///
  /// Updates without a [AgentResponseUpdate.responseId] are collected in a
  /// shared "dangling" state.
  void addUpdate(AgentResponseUpdate update) {
    final responseId = update.responseId;
    if (responseId == null) {
      _danglingState.danglingUpdates.add(update);
    } else {
      _mergeStates
          .putIfAbsent(responseId, () => _ResponseMergeState(responseId))
          .addUpdate(update);
    }
  }

  /// Merges all accumulated updates into a single [AgentResponse].
  ///
  /// [primaryResponseId] is assigned to the returned response.
  /// [primaryAgentId] and [primaryAgentName] are used to populate
  /// [AgentResponse.agentId] when a single agent id cannot be inferred.
  AgentResponse computeMerged({
    required String primaryResponseId,
    String? primaryAgentId,
    String? primaryAgentName,
  }) {
    final messages = <ChatMessage>[];
    final responses = <String, AgentResponse>{};
    final agentIds = <String>{};
    final finishReasons = <ChatFinishReason>{};

    for (final responseId in _mergeStates.keys) {
      final mergeState = _mergeStates[responseId]!;

      var responseList = <AgentResponse>[
        for (final msgId in mergeState.updatesByMessageId.keys)
          mergeState.computeMergedById(msgId),
      ];
      if (mergeState.danglingUpdates.isNotEmpty) {
        responseList.add(mergeState.computeDangling());
      }
      responseList.sort(_compareByCreatedAt);
      responses[responseId] = responseList.fold<AgentResponse?>(
        null,
        _mergeResponses,
      )!;
      messages.addAll(_messagesWithCreatedAt(responses[responseId]!));
    }

    UsageDetails? usage;
    Map<String, Object?>? additionalProperties;

    for (final response in responses.values) {
      if (response.agentId != null) agentIds.add(response.agentId!);
      if (response.finishReason != null) {
        finishReasons.add(response.finishReason!);
      }
      usage = UsageAggregator.combine(usage, response.usage);
      additionalProperties = _mergeProperties(
        additionalProperties,
        response.additionalProperties,
      );
    }

    messages.addAll(_danglingState.computeFlattened());

    for (final m in messages) {
      m.contents.removeWhere((c) => c is TextContent && c.text.trim().isEmpty);
    }
    messages.removeWhere((m) => m.contents.isEmpty);

    return AgentResponse(messages: messages)
      ..responseId = primaryResponseId
      ..agentId =
          primaryAgentId ??
          primaryAgentName ??
          (agentIds.length == 1 ? agentIds.first : null)
      ..finishReason = finishReasons.length == 1 ? finishReasons.first : null
      ..createdAt = clock.now().toUtc()
      ..usage = usage
      ..additionalProperties = additionalProperties;
  }

  static int _compareByCreatedAt(AgentResponse left, AgentResponse right) {
    if (left.createdAt == right.createdAt) return 0;
    if (left.createdAt == null) return 1;
    if (right.createdAt == null) return -1;
    return left.createdAt!.compareTo(right.createdAt!);
  }

  static AgentResponse? _mergeResponses(
    AgentResponse? current,
    AgentResponse incoming,
  ) {
    if (current == null) return incoming;
    if (current.responseId != incoming.responseId) {
      throw StateError(
        "Cannot merge responses with different IDs: "
        "'${current.responseId}' and '${incoming.responseId}'.",
      );
    }
    final rawList = <Object?>[
      if (current.rawRepresentation is List<Object?>)
        ...(current.rawRepresentation! as List<Object?>)
      else if (current.rawRepresentation != null)
        current.rawRepresentation,
      incoming.rawRepresentation,
    ];
    return AgentResponse(messages: [...current.messages, ...incoming.messages])
      ..agentId = incoming.agentId ?? current.agentId
      ..additionalProperties = _mergeProperties(
        current.additionalProperties,
        incoming.additionalProperties,
      )
      ..createdAt = incoming.createdAt ?? current.createdAt
      ..finishReason = incoming.finishReason ?? current.finishReason
      ..responseId = current.responseId
      ..rawRepresentation = rawList
      ..usage = UsageAggregator.combine(current.usage, incoming.usage);
  }

  static Iterable<ChatMessage> _messagesWithCreatedAt(AgentResponse response) {
    if (response.messages.isEmpty) return const [];
    final createdAt = response.createdAt;
    if (createdAt == null) return response.messages;
    return response.messages.map(
      (m) => ChatMessage(
        role: m.role,
        contents: m.contents,
        authorName: m.authorName,
        createdAt: createdAt,
        messageId: m.messageId,
        rawRepresentation: m.rawRepresentation,
      ),
    );
  }

  static Map<String, Object?>? _mergeProperties(
    Map<String, Object?>? current,
    Map<String, Object?>? incoming,
  ) {
    if (current == null) return incoming;
    if (incoming == null) return current;
    return {...current, ...incoming};
  }
}

class _ResponseMergeState {
  _ResponseMergeState(this.responseId);

  final String? responseId;
  final Map<String, List<AgentResponseUpdate>> updatesByMessageId = {};
  final List<AgentResponseUpdate> danglingUpdates = [];

  void addUpdate(AgentResponseUpdate update) {
    final messageId = update.messageId;
    if (messageId == null) {
      danglingUpdates.add(update);
    } else {
      updatesByMessageId.putIfAbsent(messageId, () => []).add(update);
    }
  }

  AgentResponse computeMergedById(String messageId) {
    final updates = updatesByMessageId[messageId];
    if (updates == null) {
      throw StateError(
        "No updates found for message ID '$messageId' in "
        "response '$responseId'.",
      );
    }
    return updates.toAgentResponse();
  }

  AgentResponse computeDangling() {
    if (danglingUpdates.isEmpty) {
      throw StateError('No dangling updates to compute a response from.');
    }
    return danglingUpdates.toAgentResponse();
  }

  List<ChatMessage> computeFlattened() {
    final result = <ChatMessage>[
      for (final msgId in updatesByMessageId.keys)
        ..._aggregateUpdatesToMessages(msgId),
    ];
    if (danglingUpdates.isNotEmpty) {
      result.addAll(computeDangling().messages);
    }
    return result;
  }

  List<ChatMessage> _aggregateUpdatesToMessages(String messageId) {
    final updates = updatesByMessageId[messageId]!;
    if (updates.isEmpty) {
      throw StateError(
        "No updates found for message ID '$messageId' in "
        "response '$responseId'.",
      );
    }
    return updates.toAgentResponse().messages;
  }
}
