import '../../ai_agent_builder.dart';
import 'tool_approval_agent.dart';
import 'tool_approval_agent_options.dart';

/// Provides extension methods for adding tool approval middleware to
/// [AIAgentBuilder] instances.
extension ToolApprovalAgentBuilderExtensions on AIAgentBuilder {
  /// Adds tool approval middleware to the agent pipeline, enabling "don't ask
  /// again" approval behavior and optional auto-approval rules.
  AIAgentBuilder useToolApproval({ToolApprovalAgentOptions? options}) {
    return use(
      agentFactory: (innerAgent) =>
          ToolApprovalAgent(innerAgent, options: options),
    );
  }
}
