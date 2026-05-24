/// Genkit adapters for the agents package.
///
/// Provides [GenkitFlowAgent], [GenkitToolsContextProvider],
/// [GenkitSkillsSource], and [GenkitAgentServiceCollectionExtensions] so
/// Genkit flows and tools participate in the full agent session/skill/
/// context-provider ecosystem.
library;

export 'src/genkit_agent_service_collection_extensions.dart';
export 'src/genkit_flow_agent.dart';
export 'src/genkit_skills_source.dart';
export 'src/genkit_tools_context_provider.dart';
