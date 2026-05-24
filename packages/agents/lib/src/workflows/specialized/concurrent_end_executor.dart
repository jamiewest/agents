import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../chat_protocol.dart';
import '../executor.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow_context.dart';

/// Aggregates output messages from concurrent agents.
class ConcurrentEndExecutor extends Executor<Object?, List<ChatMessage>>
    implements ResettableExecutor {
  /// Creates a [ConcurrentEndExecutor].
  ConcurrentEndExecutor(this.expectedInputs, this.aggregator)
    : super(executorId);

  /// Gets the executor identifier.
  static const String executorId = 'ConcurrentEnd';

  /// Gets the number of expected inputs.
  final int expectedInputs;

  /// Gets the aggregator function.
  final List<ChatMessage> Function(List<List<ChatMessage>> lists) aggregator;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    builder.acceptsMessage<List<Object?>>();
    builder.acceptsMessage<List<ChatMessage>>();
    builder.sendsMessage<List<ChatMessage>>();
  }

  @override
  Future<List<ChatMessage>> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final lists = _toMessageLists(message);
    return aggregator(lists);
  }

  List<List<ChatMessage>> _toMessageLists(Object? message) {
    if (message is Iterable<ChatMessage>) {
      return <List<ChatMessage>>[List<ChatMessage>.of(message)];
    }
    if (message is Iterable<Object?>) {
      final lists = <List<ChatMessage>>[];
      for (final item in message) {
        lists.add(ChatProtocol.toChatMessages(item));
      }
      return lists;
    }
    return <List<ChatMessage>>[ChatProtocol.toChatMessages(message)];
  }

  @override
  Future<bool> reset() async => true;
}
