import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../chat_protocol_executor.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';
import 'handoff_state.dart';
import 'multi_party_conversation.dart';

class HandoffConstants {
  HandoffConstants();

}
class HandoffSharedState {
  HandoffSharedState();

  final MultiPartyConversation conversation;

  String? previousAgentId;

}
/// Executor used at the start of a handoffs workflow to accumulate messages
/// and emit them as HandoffState upon receiving a turn token.
class HandoffStartExecutor extends ChatProtocolExecutor implements ResettableExecutor {
  /// Executor used at the start of a handoffs workflow to accumulate messages
  /// and emit them as HandoffState upon receiving a turn token.
  const HandoffStartExecutor(bool returnToPrevious);

  static ChatProtocolExecutorOptions get defaultOptions {
    return new()
    {
        StringMessageChatRole = ChatRole.user,
        AutoSendTurnToken = false
    };
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return super.configureProtocol(protocolBuilder).sendsMessage<HandoffState>();
  }

  @override
  Future takeTurn(
    List<ChatMessage> messages,
    WorkflowContext context,
    bool? emitEvents,
    {CancellationToken? cancellationToken, },
  ) {
    return context.invokeWithState(
            async (
              HandoffSharedState? sharedState,
              IWorkflowContext context,
              CancellationToken cancellationToken,
            ) =>
            {
                sharedState ??= handoffSharedState();
                sharedState.conversation.addMessages(messages);

                String? previousAgentId = sharedState.previousAgentId;

                // If we are configured to return to the previous agent, include the previous agent id in the handoff state.
                // If there was no previousAgent, it will still be null.
                HandoffState turnState = new(
                  new(emitEvents),
                  null,
                  returnToPrevious ? previousAgentId : null,
                );

                await context.sendMessage(turnState, cancellationToken);

                return sharedState;
            },
            HandoffConstants.handoffSharedStateKey,
            HandoffConstants.handoffSharedStateScope,
            cancellationToken);
  }

  @override
  Future reset() {
    return super.resetAsync();
  }
}
