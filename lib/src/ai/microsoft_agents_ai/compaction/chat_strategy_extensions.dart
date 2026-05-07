import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'compaction_message_index.dart';
import 'compaction_strategy.dart';

/// Provides extension methods for [CompactionStrategy].
extension ChatStrategyExtensions on CompactionStrategy {
  ChatReducer asChatReducer() => CompactionStrategyChatReducer(this);
}

/// A [ChatReducer] adapter that delegates to a [CompactionStrategy].
class CompactionStrategyChatReducer extends ChatReducer {
  CompactionStrategyChatReducer(this._strategy);

  final CompactionStrategy _strategy;

  @override
  Future<List<ChatMessage>> reduce(
    List<ChatMessage> messages, {
    CancellationToken? cancellationToken,
  }) async {
    final index = CompactionMessageIndex.create(messages);
    await _strategy.compact(index, cancellationToken: cancellationToken);
    return index.getIncludedMessages().toList();
  }
}
