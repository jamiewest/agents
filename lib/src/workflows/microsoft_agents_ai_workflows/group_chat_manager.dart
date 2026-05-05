import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
/// A manager that manages the flow of a group chat.
abstract class GroupChatManager {
  /// Initializes a new instance of the [GroupChatManager] class.
  const GroupChatManager();

  /// Gets the number of iterations in the group chat so far.
  late int iterationCount;

  /// Gets or sets the maximum number of iterations allowed.
  ///
  /// Remarks: Each iteration involves a single interaction with a participating
  /// agent. The default is 40.
  int maximumIterationCount = 40;

  /// Selects the next agent to participate in the group chat based on the
  /// provided chat history and team.
  ///
  /// Returns: The next [AIAgent] to speak. This agent must be part of the chat.
  ///
  /// [history] The chat history to consider.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<AIAgent> selectNextAgent(
    List<ChatMessage> history,
    {CancellationToken? cancellationToken, },
  );
  /// Filters the chat history before it's passed to the next agent.
  ///
  /// Returns: The filtered chat history.
  ///
  /// [history] The chat history to filter.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<Iterable<ChatMessage>> updateHistory(
    List<ChatMessage> history,
    {CancellationToken? cancellationToken, },
  ) {
    return new(history);
  }

  /// Determines whether the group chat should be terminated based on the
  /// provided chat history and iteration count.
  ///
  /// Returns: A [Boolean] indicating whether the chat should be terminated.
  ///
  /// [history] The chat history to consider.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<bool> shouldTerminate(
    List<ChatMessage> history,
    {CancellationToken? cancellationToken, },
  ) {
    return new(this.maximumIterationCount is int max && this.iterationCount >= max);
  }

  /// Resets the state of the manager for a new group chat session.
  void reset() {
    this.iterationCount = 0;
  }
}
