import 'compaction_message_index.dart';
import 'compaction_strategy.dart';

/// Defines a condition based on [CompactionMessageIndex] metrics used by a
/// [CompactionStrategy] to determine when to trigger compaction and when the
/// target compaction threshold has been met.
///
/// Returns: `true` to indicate the condition has been met; otherwise `false`.
///
/// [index] An index over conversation messages that provides group, token,
/// message, and turn metrics.
typedef CompactionTrigger = void Function();
