/// Metadata about an [AIAgent] instance for identification, telemetry,
/// and logging.
class AIAgentMetadata {
  /// Creates an [AIAgentMetadata] with an optional [providerName].
  AIAgentMetadata({this.providerName});

  /// The name of the agent provider, if applicable.
  ///
  /// Where possible, this maps to the appropriate name defined in the
  /// OpenTelemetry Semantic Conventions for Generative AI systems.
  final String? providerName;
}
