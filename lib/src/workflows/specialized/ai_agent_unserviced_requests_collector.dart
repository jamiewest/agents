import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../workflow_context.dart';
import 'ai_content_external_handler.dart';

/// Scans AI response messages for unserviced tool-approval and function-call
/// requests and submits them to registered external handlers.
class AIAgentUnservicedRequestsCollector {
  /// Creates an [AIAgentUnservicedRequestsCollector].
  AIAgentUnservicedRequestsCollector({
    this.toolApprovalHandler,
    this.functionCallHandler,
  });

  /// Gets the handler for tool-approval requests, if any.
  final AIContentExternalHandler<ToolApprovalRequestContent,
      ToolApprovalResponseContent>? toolApprovalHandler;

  /// Gets the handler for function-call requests, if any.
  final AIContentExternalHandler<FunctionCallContent,
      FunctionResultContent>? functionCallHandler;

  /// Scans [messages] for unserviced requests and submits each to the
  /// appropriate handler.
  ///
  /// Returns a list of response [AIContent] items in the order the
  /// corresponding futures resolved.
  Future<List<AIContent>> collectAsync(
    Iterable<ChatMessage> messages,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    final futures = <Future<AIContent>>[];

    for (final message in messages) {
      for (final content in message.contents) {
        if (content is ToolApprovalRequestContent) {
          final handler = toolApprovalHandler;
          if (handler != null) {
            futures.add(
              handler.handleAsync(
                content.requestId,
                content,
                context,
                cancellationToken: token,
              ),
            );
          }
        } else if (content is FunctionCallContent) {
          final handler = functionCallHandler;
          if (handler != null) {
            futures.add(
              handler.handleAsync(
                content.callId,
                content,
                context,
                cancellationToken: token,
              ),
            );
          }
        }
      }
    }

    return Future.wait(futures);
  }
}
