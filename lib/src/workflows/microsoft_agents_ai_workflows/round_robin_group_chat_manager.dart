import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import 'group_chat_manager.dart';

/// Provides a [GroupChatManager] that selects agents in a round-robin
/// fashion.
class RoundRobinGroupChatManager extends GroupChatManager {
  /// Initializes a new instance of the [RoundRobinGroupChatManager] class.
  ///
  /// [agents] The agents to be managed as part of this workflow.
  ///
  /// [shouldTerminateFunc] An optional function that determines whether the
  /// group chat should terminate based on the chat history before factoring in
  /// the default behavior, which is to terminate based only on the iteration
  /// count.
  RoundRobinGroupChatManager(
    List<AIAgent> agents,
    {Func3<RoundRobinGroupChatManager, Iterable<ChatMessage>, CancellationToken, Future<bool>>? shouldTerminateFunc = null, },
  ) : _agents = agents {
    for (final agent in agents) {
      agent;
    }
    this._shouldTerminateFunc = shouldTerminateFunc;
  }

  final List<AIAgent> _agents;

  final Func3<RoundRobinGroupChatManager, Iterable<ChatMessage>, CancellationToken, Future<bool>>? _shouldTerminateFunc;

  late int _nextIndex;

  @override
  Future<AIAgent> selectNextAgent(
    List<ChatMessage> history,
    {CancellationToken? cancellationToken, },
  ) {
    var nextAgent = this._agents[this._nextIndex];
    this._nextIndex = (this._nextIndex + 1) % this._agents.length;
    return Future<AIAgent>(nextAgent);
  }

  @override
  Future<bool> shouldTerminate(
    List<ChatMessage> history,
    {CancellationToken? cancellationToken, },
  ) async  {
    if (this._shouldTerminateFunc is { } func && await func(this, history, cancellationToken)) {
      return true;
    }
    return await super.shouldTerminateAsync(history, cancellationToken);
  }

  @override
  void reset() {
    super.reset();
    this._nextIndex = 0;
  }
}
