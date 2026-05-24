import '../../activity_stubs.dart';

/// Shared telemetry names for compaction operations.
class CompactionTelemetry {
  CompactionTelemetry._();

  static const String _sourceName = 'Microsoft.Agents.AI.Compaction';
  static final ActivitySource activitySource = ActivitySource(_sourceName);
  static final ActivityNames activityNames = ActivityNames();
  static final Tags tags = Tags();
}

/// Activity name constants for compaction telemetry spans.
class ActivityNames {
  const ActivityNames();

  /// Activity name for a compaction pass.
  String get compact => 'compact';

  /// Activity name for a compaction-provider invocation.
  String get compactionProviderInvoke => 'compaction_provider_invoke';

  /// Activity name for a summarization step.
  String get summarize => 'summarize';
}

/// Tag name constants for compaction telemetry attributes.
class Tags {
  const Tags();

  /// Tag identifying the compaction strategy used.
  String get strategy => 'compaction.strategy';

  /// Tag indicating whether compaction was triggered.
  String get triggered => 'compaction.triggered';

  /// Tag indicating whether content was actually compacted.
  String get compacted => 'compaction.compacted';

  /// Tag for the token count before compaction.
  String get beforeTokens => 'compaction.before_tokens';

  /// Tag for the token count after compaction.
  String get afterTokens => 'compaction.after_tokens';

  /// Tag for the message count before compaction.
  String get beforeMessages => 'compaction.before_messages';

  /// Tag for the message count after compaction.
  String get afterMessages => 'compaction.after_messages';

  /// Tag for the group count before compaction.
  String get beforeGroups => 'compaction.before_groups';

  /// Tag for the group count after compaction.
  String get afterGroups => 'compaction.after_groups';

  /// Tag for the elapsed compaction time in milliseconds.
  String get durationMs => 'compaction.duration_ms';

  /// Tag for the number of groups that were summarized.
  String get groupsSummarized => 'compaction.groups_summarized';

  /// Tag for the character length of the produced summary.
  String get summaryLength => 'compaction.summary_length';
}
