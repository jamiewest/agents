import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../chat_protocol_executor.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../turn_token.dart';
import '../workflow_context.dart';

/// Provides an executor that batches received chat messages that it then
/// publishes as the final result when receiving a [TurnToken].
class OutputMessagesExecutor extends ChatProtocolExecutor implements ResettableExecutor {
  /// Provides an executor that batches received chat messages that it then
  /// publishes as the final result when receiving a [TurnToken].
  OutputMessagesExecutor({ChatProtocolExecutorOptions? options = null});

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return super.configureProtocol(protocolBuilder)
            .yieldsOutput<List<ChatMessage>>();
  }

  @override
  Future takeTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    bool? emitEvents,
    {CancellationToken? cancellationToken, }
  ) {
    return context.yieldOutput(messages, cancellationToken);
  }

  Future reset() {
    return Future.value(null);
  }
}
