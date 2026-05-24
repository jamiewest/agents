import 'workflow_telemetry_options.dart';

/// No-op telemetry context.
///
/// The C# implementation uses `System.Diagnostics.ActivitySource` which is out
/// of scope for this Dart port. This stub preserves the type boundary so that
/// dependent code can compile without ActivitySource.
class WorkflowTelemetryContext {
  /// Creates a [WorkflowTelemetryContext].
  WorkflowTelemetryContext([WorkflowTelemetryOptions? options]);
}
