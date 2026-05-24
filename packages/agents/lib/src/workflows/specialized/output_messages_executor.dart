import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../chat_protocol.dart';
import '../executor.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';

/// Batches received chat messages and publishes them as the final result.
class OutputMessagesExecutor extends Executor<Object?, List<ChatMessage>>
    implements ResettableExecutor {
  /// Creates an [OutputMessagesExecutor].
  OutputMessagesExecutor() : super(executorId);

  /// Gets the executor identifier.
  static const String executorId = 'OutputMessages';

  @override
  void configureProtocol(ProtocolBuilder builder) {
    ChatProtocol.configureInput(builder);
    builder.sendsMessage<List<ChatMessage>>();
  }

  @override
  Future<List<ChatMessage>> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return ChatProtocol.toChatMessages(message);
  }

  @override
  Future<bool> reset() async => true;
}
