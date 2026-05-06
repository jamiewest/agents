import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_trigger.dart';
import 'compaction_triggers.dart';

/// A compaction strategy that delegates to an [ChatReducer] to reduce the
/// conversation's included messages.
///
/// Remarks: This strategy bridges the [ChatReducer] abstraction from
/// `Microsoft.Extensions.AI` into the compaction pipeline. It collects the
/// currently included messages from the [CompactionMessageIndex], passes them
/// to the reducer, and rebuilds the index from the reduced message list when
/// the reducer produces fewer messages. The [CompactionTrigger] controls when
/// reduction is attempted. Use [CompactionTriggers] for common trigger
/// conditions such as token or message thresholds. Use this strategy when you
/// have an existing [ChatReducer] implementation (such as
/// `MessageCountingChatReducer`) and want to apply it as part of a
/// [CompactionStrategy] pipeline or as an in-run compaction strategy.
class ChatReducerCompactionStrategy extends CompactionStrategy {
  /// Initializes a new instance of the [ChatReducerCompactionStrategy] class.
  ///
  /// [chatReducer] The [ChatReducer] that performs the message reduction.
  ///
  /// [trigger] The [CompactionTrigger] that controls when compaction proceeds.
  ChatReducerCompactionStrategy(
    ChatReducer chatReducer,
    CompactionTrigger trigger,
  ) : chatReducer = chatReducer, super(trigger) {
  }

  /// Gets the chat reducer used to reduce messages.
  final ChatReducer chatReducer;

  @override
  Future<bool> compactCore(
    CompactionMessageIndex index,
    Logger logger,
    CancellationToken cancellationToken,
  ) async {
    var includedMessages = [...index.getIncludedMessages()];
    var reduced = await this.chatReducer.reduceAsync(
      includedMessages,
      cancellationToken,
    ) ;
    var reducedMessages = [...reduced];
    if (reducedMessages.length >= includedMessages.length) {
      return false;
    }
    var rebuilt = CompactionMessageIndex.create(reducedMessages, index.tokenizer);
    index.groups.clear();
    for (final group in rebuilt.groups) {
      index.groups.add(group);
    }
    return true;
  }
}
