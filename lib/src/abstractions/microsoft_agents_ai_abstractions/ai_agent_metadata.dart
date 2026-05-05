/// Provides metadata information about an [AIAgent] instance.
///
/// Remarks: This class contains descriptive information about an agent that
/// can be used for identification, telemetry, and logging purposes.
class AIAgentMetadata {
  /// Creates an [AIAgentMetadata] with an optional [providerName].
  AIAgentMetadata({this.providerName});

  /// The name of the agent provider, if applicable.
  ///
  /// Remarks: Where possible, this maps to the appropriate name defined in the
  /// OpenTelemetry Semantic Conventions for Generative AI systems.
  final String? providerName;
}
