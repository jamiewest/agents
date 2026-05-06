import 'ai_agent_builder.dart';
import 'open_telemetry_agent.dart';
import '../../func_typedefs.dart';

/// Provides extension methods for adding OpenTelemetry instrumentation to
/// [AIAgentBuilder] instances.
extension OpenTelemetryAgentBuilderExtensions on AIAgentBuilder {
  /// Adds OpenTelemetry instrumentation to the agent pipeline, enabling
/// comprehensive observability for agent operations.
///
/// Remarks: This extension adds comprehensive telemetry capabilities to AI
/// agents, including: Distributed tracing of agent invocations Performance
/// metrics and timing information Request and response payload logging (when
/// enabled) Error tracking and exception details Usage statistics and token
/// consumption metrics The implementation follows the OpenTelemetry Semantic
/// Conventions for Generative AI systems as defined at . Note: The
/// OpenTelemetry specification for Generative AI is still experimental and
/// subject to change. As the specification evolves, the telemetry output from
/// this agent may also change to maintain compliance.
///
/// Returns: The [AIAgentBuilder] with OpenTelemetry instrumentation added,
/// enabling method chaining.
///
/// [builder] The [AIAgentBuilder] to which OpenTelemetry support will be
/// added.
///
/// [sourceName] An optional source name that will be used to identify
/// telemetry data from this agent. If not specified, a default source name
/// will be used.
///
/// [configure] An optional callback that provides additional configuration of
/// the [OpenTelemetryAgent] instance. This allows for fine-tuning telemetry
/// behavior such as enabling sensitive data collection.
AIAgentBuilder useOpenTelemetry({String? sourceName, Action<OpenTelemetryAgent>? configure, }) {
return builder.use((innerAgent, services) {
        
            var agent = openTelemetryAgent(innerAgent, sourceName);
            configure?.invoke(agent);

            return agent;
        });
 }
 }
