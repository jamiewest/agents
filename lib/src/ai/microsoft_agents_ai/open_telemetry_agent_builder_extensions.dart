import '../../func_typedefs.dart';
import 'ai_agent_builder.dart';
import 'open_telemetry_agent.dart';

/// Provides extension methods for adding OpenTelemetry instrumentation to
/// [AIAgentBuilder] instances.
extension OpenTelemetryAgentBuilderExtensions on AIAgentBuilder {
  /// Adds OpenTelemetry instrumentation to the agent pipeline.
  AIAgentBuilder useOpenTelemetry({
    String? sourceName,
    Action1<OpenTelemetryAgent>? configure,
  }) {
    return useFactory((innerAgent, _) {
      final agent = OpenTelemetryAgent(innerAgent, sourceName: sourceName);
      configure?.call(agent);
      return agent;
    });
  }
}
