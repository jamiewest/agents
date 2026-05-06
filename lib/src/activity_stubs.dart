/// Stub types for .NET System.Diagnostics.Activity / OpenTelemetry tracing.
/// These are placeholders until a proper Dart OpenTelemetry integration is
/// implemented. All methods are no-ops in this stub implementation.

/// Mirrors System.Diagnostics.ActivityKind.
enum ActivityKind {
  internal,
  server,
  client,
  producer,
  consumer,
}

/// Mirrors System.Diagnostics.ActivityStatusCode.
enum ActivityStatusCode {
  unset,
  ok,
  error,
}

/// Mirrors System.Diagnostics.ActivityEvent.
class ActivityEvent {
  const ActivityEvent(this.name, {this.tags = const {}});
  final String name;
  final Map<String, Object?> tags;
}

/// Mirrors System.Diagnostics.Activity.
class Activity {
  Activity(this.operationName);

  final String operationName;
  String? displayName;
  static Activity? current;

  void addEvent(ActivityEvent event) {}
  Activity setTag(String key, Object? value) => this;
  Activity setStatus(ActivityStatusCode code, [String? description]) => this;
  void dispose() {}
  void stop() {}
}

/// Mirrors System.Diagnostics.ActivitySource.
class ActivitySource {
  ActivitySource(this.name, [this.version = '']);

  final String name;
  final String version;

  Activity? startActivity(String name, [ActivityKind? kind]) => null;

  void dispose() {}
}

/// Factory function to create an [ActivityEvent] (mirrors C# constructor call
/// pattern `new ActivityEvent(name, ...)`).
ActivityEvent activityEvent(
  String name, {
  Map<String, Object?> tags = const {},
}) {
  return ActivityEvent(name, tags: tags);
}
