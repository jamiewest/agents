import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';
import 'workflow_host_agent.dart';

/// Provides extension methods for treating workflows as [AIAgent]
extension WorkflowHostingExtensions on Workflow {
  /// Convert a workflow with the appropriate primary input type to an
/// [AIAgent].
///
/// Returns:
///
/// [workflow] The workflow to be hosted by the resulting [AIAgent]
///
/// [id] A unique id for the hosting [AIAgent].
///
/// [name] A name for the hosting [AIAgent].
///
/// [description] A description for the hosting [AIAgent].
///
/// [executionEnvironment] Specify the execution environment to use when
/// running the workflows. See [OffThread], [Concurrent] and [Lockstep] for
/// the in-process environments.
///
/// [includeExceptionDetails] If `true`, will include [Message] in the
/// [ErrorContent] representing the workflow error.
///
/// [includeWorkflowOutputsInResponse] If `true`, will transform outgoing
/// workflow outputs into into content in [AgentResponseUpdate]s or the
/// [AgentResponse] as appropriate.
AIAgent asAIAgent({String? id, String? name, String? description, WorkflowExecutionEnvironment? executionEnvironment, bool? includeExceptionDetails, bool? includeWorkflowOutputsInResponse, }) {
return workflowHostAgent(
  workflow,
  id,
  name,
  description,
  executionEnvironment,
  includeExceptionDetails,
  includeWorkflowOutputsInResponse,
);
 }
FunctionCallContent toFunctionCall() {
var parameters = new()
        {
            { "data", request.data }
        };
return functionCallContent(request.requestId, request.portInfo.portId, parameters);
 }
 }
