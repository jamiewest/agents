import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import 'ai_agent_builder.dart';

/// Provides extensions for [AIAgent].
extension AIAgentExtensions on AIAgent {
  /// Creates a new [AIAgentBuilder] using the specified agent as the foundation
/// for the builder pipeline.
///
/// Remarks: This method provides a convenient way to convert an existing
/// [AIAgent] instance into a builder pattern, enabling easily wrapping the
/// agent in layers of additional functionality. It is functionally equivalent
/// to using the [AIAgent)] constructor directly, but provides a more fluent
/// API when working with existing agent instances.
///
/// Returns: A new [AIAgentBuilder] instance configured with the specified
/// inner agent.
///
/// [innerAgent] The [AIAgent] instance to use as the inner agent.
AIAgentBuilder asBuilder() {
return aiAgentBuilder(innerAgent);
 }
/// Creates an [AIFunction] that runs the provided [AIAgent].
///
/// Remarks: This extension method enables agents to participate in function
/// calling scenarios, where they can be invoked as tools by other agents or
/// AI models. The resulting function accepts a query String as input and
/// returns the agent's response as a String, making it compatible with
/// standard function calling interfaces used by AI models. The resulting
/// [AIFunction] is stateful, referencing both the `agent` and the optional
/// `session`. Especially if a specific session is provided, avoid using the
/// resulting function concurrently in multiple conversations or in requests
/// where the parallel function calls may result in concurrent usage of the
/// session, as that could lead to undefined and unpredictable behavior.
///
/// Returns: An [AIFunction] that can be used as a tool by other agents or AI
/// models to invoke this agent.
///
/// [agent] The [AIAgent] to be represented as an invocable function.
///
/// [options] Optional metadata to customize the function representation, such
/// as name and description. If not provided, defaults will be inferred from
/// the agent's properties.
///
/// [session] Optional [AgentSession] to use for function invocations. If not
/// provided, a new session will be created for each function call, which may
/// not preserve conversation context.
AIFunction asAIFunction({AIFunctionFactoryOptions? options, AgentSession? session, }) {
/* TODO: unsupported node kind "unknown" */
// [Description("Invoke an agent to retrieve some information.")]
//         async Task<String> InvokeAgentAsync(
//             [Description("Input query to invoke the agent.")] String query,
//             CancellationToken cancellationToken)
//         {
//             // Propagate any additional properties from the parent agent's run to the child agent if the parent is using a FunctionInvokingChatClient.
//             AgentRunOptions? agentRunOptions = FunctionInvokingChatClient.CurrentContext?.Options?.AdditionalProperties is AdditionalPropertiesDictionary
//                 ? new AgentRunOptions { AdditionalProperties = dict }
//                 : null;
//
//             var response = await agent.RunAsync(query, session: session, options: agentRunOptions, cancellationToken: cancellationToken);
//             return response.Text;
//         }
options ??= AIFunctionFactoryOptions();
options.name ??= sanitizeAgentName(agent.name);
options.description ??= agent.description;
return AIFunctionFactory.create(InvokeAgentAsync, options);
 }
 }
