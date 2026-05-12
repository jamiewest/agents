import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../abstractions/ai_agent.dart';
import 'group_chat_manager.dart';

/// Provides a [GroupChatManager] that selects agents in round-robin order.
class RoundRobinGroupChatManager extends GroupChatManager {
  /// Initializes a new instance of the [RoundRobinGroupChatManager] class.
  RoundRobinGroupChatManager(
    Iterable<AIAgent> agents, {
    this.shouldTerminateFunc,
  }) : _agents = List<AIAgent>.of(agents) {
    if (_agents.isEmpty) {
      throw ArgumentError.value(agents, 'agents', 'Agents cannot be empty.');
    }
  }

  final List<AIAgent> _agents;
  final Future<bool> Function(
    RoundRobinGroupChatManager manager,
    Iterable<ChatMessage> history,
    CancellationToken? cancellationToken,
  )?
  shouldTerminateFunc;

  int _nextIndex = 0;

  @override
  Future<AIAgent> selectNextAgent(
    List<ChatMessage> history, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final nextAgent = _agents[_nextIndex];
    _nextIndex = (_nextIndex + 1) % _agents.length;
    return nextAgent;
  }

  @override
  Future<bool> shouldTerminate(
    List<ChatMessage> history, {
    CancellationToken? cancellationToken,
  }) async {
    final custom = shouldTerminateFunc;
    if (custom != null &&
        await custom(
          this,
          history,
          cancellationToken ?? CancellationToken.none,
        )) {
      return true;
    }
    return super.shouldTerminate(history, cancellationToken: cancellationToken);
  }

  @override
  void reset() {
    super.reset();
    _nextIndex = 0;
  }
}
