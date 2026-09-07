import 'package:extensions/system.dart';

import 'a2a_run_decision_context.dart';

/// A delegate that decides whether a new-message response is returned as an
/// `AgentTask`.
///
/// Returns `true` to return an `AgentTask`, or `false` to return an
/// `AgentMessage`.
typedef ReturnTaskCallback =
    Future<bool> Function(
      A2ARunDecisionContext context,
      CancellationToken? cancellationToken,
    );

/// Specifies which A2A protocol artifact the hosting layer returns for a run
/// of an agent: an `AgentMessage` or an `AgentTask`.
final class AgentRunMode {
  const AgentRunMode._(this._value, [this._returnTask]);

  static const String _messageValue = 'message';
  static const String _taskValue = 'task';
  static const String _dynamicValue = 'dynamic';

  final String _value;
  final ReturnTaskCallback? _returnTask;

  /// Returns the agent response as an `AgentMessage`.
  ///
  /// The updates produced by the agent are aggregated into a single message.
  static const AgentRunMode returnMessage = AgentRunMode._(_messageValue);

  /// Returns the agent response as an `AgentTask`, allowing the caller to
  /// track its lifecycle and to receive the result incrementally.
  static const AgentRunMode returnTask = AgentRunMode._(_taskValue);

  /// Defers the choice between an `AgentMessage` and an `AgentTask` to the
  /// supplied [returnTask] delegate, which is invoked for each new-message
  /// request.
  ///
  /// The delegate receives an [A2ARunDecisionContext] describing the incoming
  /// request and returns `true` to return an `AgentTask`, or `false` to
  /// return an `AgentMessage`. Continuations of an existing task remain task
  /// responses and do not invoke the delegate.
  static AgentRunMode returnTaskWhen(ReturnTaskCallback returnTask) {
    return AgentRunMode._(_dynamicValue, returnTask);
  }

  /// Determines whether the agent response should be returned as an
  /// `AgentTask` for the given [context].
  Future<bool> shouldReturnTask(
    A2ARunDecisionContext context, {
    CancellationToken? cancellationToken,
  }) {
    if (_value == _messageValue) {
      return Future.value(false);
    }
    if (_value == _taskValue) {
      return Future.value(true);
    }
    final returnTask = _returnTask;
    if (returnTask != null) {
      return returnTask(context, cancellationToken);
    }
    // No delegate provided — fall back to "message" behavior.
    return Future.value(false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentRunMode &&
          _value == other._value &&
          identical(_returnTask, other._returnTask);

  @override
  int get hashCode => Object.hash(_value, identityHashCode(_returnTask));

  @override
  String toString() => _value;
}
