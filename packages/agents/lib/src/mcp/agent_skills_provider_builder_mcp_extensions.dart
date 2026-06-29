import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../ai/skills/agent_skills_provider_builder.dart';
import 'agent_mcp_skills_source.dart';
import 'agent_mcp_skills_source_options.dart';

/// MCP-specific extensions for [AgentSkillsProviderBuilder].
extension AgentSkillsProviderBuilderMcpExtensions
    on AgentSkillsProviderBuilder {
  /// Adds skills discovered from an MCP server.
  AgentSkillsProviderBuilder useMcpSkills(
    mcp.McpClient client, {
    AgentMcpSkillsSourceOptions? options,
  }) {
    return useSource(AgentMcpSkillsSource(client, options: options));
  }
}
