/// Provides constants used by the agent telemetry services.
abstract final class OpenTelemetryConsts {
  static const String defaultSourceName = 'Microsoft.Agents.AI';

  static const OpenTelemetryGenAI genAI = OpenTelemetryGenAI();
}

class OpenTelemetryGenAI {
  const OpenTelemetryGenAI();

  String get invokeAgent => 'invoke_agent';
  OpenTelemetryOperation get operation => const OpenTelemetryOperation();
  OpenTelemetryProvider get provider => const OpenTelemetryProvider();
  OpenTelemetryAgentTags get agent => const OpenTelemetryAgentTags();
}

class OpenTelemetryOperation {
  const OpenTelemetryOperation();
  String get name => 'gen_ai.operation.name';
}

class OpenTelemetryProvider {
  const OpenTelemetryProvider();
  String get name => 'gen_ai.system';
}

class OpenTelemetryAgentTags {
  const OpenTelemetryAgentTags();
  String get id => 'gen_ai.agent.id';
  String get name => 'gen_ai.agent.name';
  String get description => 'gen_ai.agent.description';
}
