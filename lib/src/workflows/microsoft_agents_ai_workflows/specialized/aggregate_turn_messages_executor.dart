import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../chat_protocol_executor.dart';
import '../resettable_executor.dart';
import '../turn_token.dart';
import '../workflow_context.dart';

/// Provides an executor that aggregates received chat messages that it then
/// releases when receiving a [TurnToken].
class AggregateTurnMessagesExecutor extends ChatProtocolExecutor
    implements ResettableExecutor {
  /// Provides an executor that aggregates received chat messages that it then
  /// releases when receiving a [TurnToken].
  const AggregateTurnMessagesExecutor(String id);

  static final ChatProtocolExecutorOptions s_options;

  @override
  Future takeTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    bool? emitEvents, {
    CancellationToken? cancellationToken,
  }) {
    return context.sendMessage(
      messages,
      cancellationToken: cancellationToken,
    );
  }

  Future reset() {
    return this.resetAsync();
  }
}
