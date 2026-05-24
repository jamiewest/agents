import 'compaction_message_index.dart';

/// Defines a condition based on [CompactionMessageIndex] metrics.
typedef CompactionTrigger = bool Function(CompactionMessageIndex index);
