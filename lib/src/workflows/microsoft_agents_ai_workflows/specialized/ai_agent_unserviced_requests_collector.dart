import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import 'package:extensions/system.dart';
import '../../../func_typedefs.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../workflow_context.dart';
import 'ai_content_external_handler.dart';

class AIAgentUnservicedRequestsCollector {
  const AIAgentUnservicedRequestsCollector(
    AIContentExternalHandler<
      ToolApprovalRequestContent,
      ToolApprovalResponseContent
    >?
    userInputHandler,
    AIContentExternalHandler<FunctionCallContent, FunctionResultContent>?
    functionCallHandler,
  );

  final Map<String, ToolApprovalRequestContent> _userInputRequests = {};

  final Map<String, FunctionCallContent> _functionCalls = {};

  Future submit(WorkflowContext context, CancellationToken cancellationToken) {
    var userInputTask =
        userInputHandler != null && this._userInputRequests.length > 0
        ? userInputHandler.processRequestContentsAsync(
            this._userInputRequests,
            context,
            cancellationToken,
          )
        : Task.value(null);
    var functionCallTask =
        functionCallHandler != null && this._functionCalls.length > 0
        ? functionCallHandler.processRequestContentsAsync(
            this._functionCalls,
            context,
            cancellationToken,
          )
        : Task.value(null);
    return Future.wait(userInputTask, functionCallTask);
  }

  void processAgentResponseUpdate(
    AgentResponseUpdate update, {
    Func<FunctionCallContent, bool>? functionCallFilter,
  }) {
    this.processAIContents(update.contents, functionCallFilter);
  }

  void processAgentResponse(AgentResponse response) {
    this.processAIContents(
      response.messages.expand((message) => message.contents),
    );
  }

  void processAIContents(
    Iterable<AIContent> contents, {
    Func<FunctionCallContent, bool>? functionCallFilter,
  }) {
    for (final content in contents) {
      if (content is ToolApprovalRequestContent) {
        final userInputRequest = content as ToolApprovalRequestContent;
        if (this._userInputRequests.containsKey(userInputRequest.requestId)) {
          throw StateError(
            'ToolApprovalRequestContent with duplicate RequestId: ${userInputRequest.requestId}',
          );
        }
        // It is an error to simultaneously have multiple outstanding user input requests with the same ID.
        this._userInputRequests.add(
          userInputRequest.requestId,
          userInputRequest,
        );
      } else if (content is ToolApprovalResponseContent) {
        final userInputResponse = content as ToolApprovalResponseContent;
        // If the set of messages somehow already has a corresponding user input response, remove it.
        _ = this._userInputRequests.remove(userInputResponse.requestId);
      } else if (content is FunctionCallContent) {
        final functionCall = content as FunctionCallContent;
        if (functionCallFilter == null || functionCallFilter(functionCall)) {
          if (this._functionCalls.containsKey(functionCall.callId)) {
            throw StateError(
              'FunctionCallContent with duplicate CallId: ${functionCall.callId}',
            );
          }
          this._functionCalls.add(functionCall.callId, functionCall);
        }
      } else if (content is FunctionResultContent) {
        final functionResult = content as FunctionResultContent;
        _ = this._functionCalls.remove(functionResult.callId);
      }
    }
  }
}
