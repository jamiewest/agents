import '../../ai_agent_builder.dart';
import 'always_approve_tool_approval_response_content.dart';
import 'tool_approval_agent.dart';
import '../../../../json_stubs.dart';

/// Provides extension methods for adding tool approval middleware to
/// [AIAgentBuilder] instances.
extension ToolApprovalAgentBuilderExtensions on AIAgentBuilder {
  /// Adds tool approval middleware to the agent pipeline, enabling "don't ask
  /// again" approval behavior.
  ///
  /// Remarks: The [ToolApprovalAgent] middleware intercepts tool approval flows
  /// between the caller and the inner agent. When a caller responds with an
  /// [AlwaysApproveToolApprovalResponseContent], the middleware records a
  /// standing approval rule so that future matching tool calls are
  /// auto-approved without user interaction.
  ///
  /// Returns: The [AIAgentBuilder] with tool approval middleware added,
  /// enabling method chaining.
  ///
  /// [builder] The [AIAgentBuilder] to which tool approval support will be
  /// added.
  ///
  /// [JsonSerializerOptions] Optional [JsonSerializerOptions] used for
  /// serializing argument values when storing rules and for persisting state.
  /// When `null`, [DefaultOptions] is used.
  AIAgentBuilder useToolApproval({
    JsonSerializerOptions? JsonSerializerOptions,
  }) {
    return use(agentFactory: (innerAgent) => ToolApprovalAgent(innerAgent, JsonSerializerOptions: JsonSerializerOptions));
  }
}
