import '../../activity_stubs.dart';

/// Shared telemetry names for compaction operations.
class CompactionTelemetry {
  CompactionTelemetry._();

  static const String _sourceName = 'Microsoft.Agents.AI.Compaction';
  static final ActivitySource activitySource = ActivitySource(_sourceName);
  static final ActivityNames activityNames = ActivityNames();
  static final Tags tags = Tags();
}

class ActivityNames {
  const ActivityNames();

  String get compact => 'compact';
  String get compactionProviderInvoke => 'compaction_provider_invoke';
  String get summarize => 'summarize';
}

class Tags {
  const Tags();

  String get strategy => 'compaction.strategy';
  String get triggered => 'compaction.triggered';
  String get compacted => 'compaction.compacted';
  String get beforeTokens => 'compaction.before_tokens';
  String get afterTokens => 'compaction.after_tokens';
  String get beforeMessages => 'compaction.before_messages';
  String get afterMessages => 'compaction.after_messages';
  String get beforeGroups => 'compaction.before_groups';
  String get afterGroups => 'compaction.after_groups';
  String get durationMs => 'compaction.duration_ms';
  String get groupsSummarized => 'compaction.groups_summarized';
  String get summaryLength => 'compaction.summary_length';
}
