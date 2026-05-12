/// Provides constants used by the agent telemetry services.
abstract final class OpenTelemetryConsts {
  static const String defaultSourceName = 'Microsoft.Agents.AI';

  static const OpenTelemetryGenAI genAI = OpenTelemetryGenAI();
}

/// OpenTelemetry attribute name constants for generative-AI operations.
class OpenTelemetryGenAI {
  const OpenTelemetryGenAI();

  /// Span name used when invoking an agent.
  String get invokeAgent => 'invoke_agent';

  /// Operation-dimension attribute names.
  OpenTelemetryOperation get operation => const OpenTelemetryOperation();

  /// Provider-dimension attribute names.
  OpenTelemetryProvider get provider => const OpenTelemetryProvider();

  /// Agent-identity attribute names.
  OpenTelemetryAgentTags get agent => const OpenTelemetryAgentTags();
}

/// OpenTelemetry attribute name constants for the operation dimension.
class OpenTelemetryOperation {
  const OpenTelemetryOperation();

  /// Attribute key for the operation name.
  String get name => 'gen_ai.operation.name';
}

/// OpenTelemetry attribute name constants for the AI provider dimension.
class OpenTelemetryProvider {
  const OpenTelemetryProvider();

  /// Attribute key for the provider/system name.
  String get name => 'gen_ai.system';
}

/// OpenTelemetry attribute name constants for the agent identity dimension.
class OpenTelemetryAgentTags {
  const OpenTelemetryAgentTags();

  /// Attribute key for the agent identifier.
  String get id => 'gen_ai.agent.id';

  /// Attribute key for the agent display name.
  String get name => 'gen_ai.agent.name';

  /// Attribute key for the agent description.
  String get description => 'gen_ai.agent.description';
}
