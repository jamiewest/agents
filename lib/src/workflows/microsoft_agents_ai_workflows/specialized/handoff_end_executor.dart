import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';
import 'handoff_agent_executor.dart';
import 'handoff_start_executor.dart';
import 'handoff_state.dart';

/// Executor used at the end of a handoff workflow to raise a final completed
/// event.
class HandoffEndExecutor extends Executor implements ResettableExecutor {
  /// Executor used at the end of a handoff workflow to raise a final completed
  /// event.
  const HandoffEndExecutor(bool returnToPrevious);

  final StateRef<HandoffSharedState> _sharedStateRef;

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return protocolBuilder.configureRoutes((routeBuilder) => routeBuilder.addHandler<HandoffState>(
                                            (
                                              handoff,
                                              context,
                                              cancellationToken,
                                            ) => this.handleAsync(handoff, context, cancellationToken)))
                       .yieldsOutput<List<ChatMessage>>();
  }

  Future handle(
    HandoffState handoff,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) async  {
    await this._sharedStateRef.invokeWithState(
            async (
              HandoffSharedState? sharedState,
              IWorkflowContext context,
              CancellationToken cancellationToken,
            ) =>
            {
                if (sharedState == null)
                {
                    throw StateError("Handoff Orchestration shared state was not properly initialized.");
      }

                if (returnToPrevious)
                {
                    sharedState.previousAgentId = handoff.previousAgentId;
      }

                await context.yieldOutput(
                  sharedState.conversation.cloneAllMessages(),
                  cancellationToken,
                ) ;

                return sharedState;
            }, context, cancellationToken);
  }

  @override
  Future reset() {
    return Future.value(null);
  }
}
