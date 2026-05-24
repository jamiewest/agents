import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../executor.dart';
import '../protocol_builder.dart';
import '../workflow_context.dart';
import 'handoff_state.dart';
import 'multi_party_conversation.dart';

/// Terminates a handoff workflow by emitting the accumulated conversation
/// history from [conversation].
class HandoffEndExecutor extends Executor<HandoffState, List<ChatMessage>> {
  /// Creates a [HandoffEndExecutor].
  HandoffEndExecutor(this.conversation) : super(executorId);

  /// Gets the fixed executor identifier.
  static const String executorId = 'HandoffEnd';

  /// Gets the shared multi-party conversation.
  final MultiPartyConversation conversation;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    builder.acceptsMessage<HandoffState>();
    builder.sendsMessage<List<ChatMessage>>();
  }

  @override
  Future<List<ChatMessage>> handle(
    HandoffState message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return conversation.cloneHistory();
  }
}
