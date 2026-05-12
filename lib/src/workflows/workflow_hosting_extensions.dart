import 'package:extensions/ai.dart';

import '../abstractions/ai_agent.dart';
import 'external_request.dart';
import 'workflow.dart';
import 'workflow_execution_environment.dart';
import 'workflow_host_agent.dart';

/// Extension methods for hosting a [Workflow] as an [AIAgent].
extension WorkflowHostingExtensions on Workflow {
  /// Wraps this workflow in a [WorkflowHostAgent].
  ///
  /// [name] and [description] override the values from the workflow.
  /// [executionEnvironment] controls how the workflow is executed; defaults to
  /// the in-process environment.
  AIAgent asAIAgent({
    String? name,
    String? description,
    WorkflowExecutionEnvironment? executionEnvironment,
  }) => WorkflowHostAgent(
    this,
    executionEnvironment: executionEnvironment,
    name: name,
    description: description,
  );
}

/// Extension methods for [ExternalRequest].
extension ExternalRequestExtensions<TRequest, TResponse>
    on ExternalRequest<TRequest, TResponse> {
  /// Converts this request to a [FunctionCallContent] for use in a chat
  /// message, with the request payload under the `"data"` key.
  FunctionCallContent toFunctionCall() => FunctionCallContent(
    callId: requestId,
    name: port.id,
    arguments: {'data': request},
  );
}
