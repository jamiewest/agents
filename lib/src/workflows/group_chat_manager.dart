import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../abstractions/ai_agent.dart';

/// A manager that manages the flow of a group chat.
abstract class GroupChatManager {
  /// Initializes a new instance of the [GroupChatManager] class.
  GroupChatManager();

  /// Gets the number of iterations in the group chat so far.
  int iterationCount = 0;

  int _maximumIterationCount = 40;

  /// Gets or sets the maximum number of iterations allowed.
  ///
  /// Each iteration involves a single interaction with a participating agent.
  /// The default is 40.
  int get maximumIterationCount => _maximumIterationCount;
  set maximumIterationCount(int value) {
    if (value < 1) {
      throw RangeError.range(value, 1, null, 'value');
    }
    _maximumIterationCount = value;
  }

  /// Selects the next agent to participate in the group chat.
  Future<AIAgent> selectNextAgent(
    List<ChatMessage> history, {
    CancellationToken? cancellationToken,
  });

  /// Filters the chat history before it is passed to the next agent.
  Future<Iterable<ChatMessage>> updateHistory(
    List<ChatMessage> history, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return history;
  }

  /// Determines whether the group chat should be terminated.
  Future<bool> shouldTerminate(
    List<ChatMessage> history, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    return iterationCount >= maximumIterationCount;
  }

  /// Resets the state of the manager for a new group chat session.
  void reset() {
    iterationCount = 0;
  }
}
