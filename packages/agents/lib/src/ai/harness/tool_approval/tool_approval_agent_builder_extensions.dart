import '../../ai_agent_builder.dart';
import '../../../json_stubs.dart';
import 'tool_approval_agent.dart';

/// Provides extension methods for adding tool approval middleware to
/// [AIAgentBuilder] instances.
extension ToolApprovalAgentBuilderExtensions on AIAgentBuilder {
  /// Adds tool approval middleware to the agent pipeline, enabling "don't ask
  /// again" approval behavior.
  AIAgentBuilder useToolApproval({
    JsonSerializerOptions? jsonSerializerOptions,
  }) {
    return use(
      agentFactory: (innerAgent) => ToolApprovalAgent(
        innerAgent,
        jsonSerializerOptions: jsonSerializerOptions,
      ),
    );
  }
}
