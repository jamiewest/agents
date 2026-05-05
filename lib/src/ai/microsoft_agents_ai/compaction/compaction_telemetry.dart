import '../../../activity_stubs.dart';
import '../open_telemetry_consts.dart';

/// Provides shared telemetry infrastructure for compaction operations.
class CompactionTelemetry {
  CompactionTelemetry();

  static const String _sourceName = 'Microsoft.Agents.AI.Compaction';

  /// The [ActivitySource] used to create activities for compaction operations.
  static final ActivitySource activitySource = ActivitySource(_sourceName);

}
/// Activity names used by compaction tracing.
class ActivityNames {
  ActivityNames();

}
/// Tag names used on compaction activities.
class Tags {
  Tags();

}
