import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'chat_protocol.dart';
import 'executor.dart';
import 'protocol_builder.dart';
import 'workflow_context.dart';

/// Forwards chat protocol messages to another workflow executor.
class ChatForwardingExecutor extends Executor<Object?, void> {
  /// Creates a forwarding executor that sends chat messages to [targetExecutorId].
  ChatForwardingExecutor(super.id, this.targetExecutorId);

  /// Gets the target executor identifier.
  final String targetExecutorId;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    ChatProtocol.configureInput(builder);
    builder.sendsMessage<ChatMessage>();
  }

  @override
  Future<void> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    for (final chatMessage in ChatProtocol.toChatMessages(message)) {
      await context.sendMessage(
        chatMessage,
        targetExecutorId: targetExecutorId,
        cancellationToken: cancellationToken,
      );
    }
  }
}
