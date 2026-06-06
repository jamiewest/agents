import 'package:extensions/system.dart';

import 'a2a_run_decision_context.dart';

/// A delegate that decides whether an agent run should be wrapped in a
/// background A2A task.
///
/// Returns `true` to run in background mode (returning an `AgentTask` when the
/// agent supports it), or `false` to run inline (returning an `AgentMessage`).
typedef RunInBackgroundCallback =
    Future<bool> Function(
      A2ARunDecisionContext context,
      CancellationToken? cancellationToken,
    );

/// Specifies how the A2A hosting layer decides whether to run an agent in
/// background mode.
///
/// Mirrors the semantics of the underlying
/// `AgentRunOptions.allowBackgroundResponses` flag, translated into A2A
/// protocol terms: background runs surface as an `AgentTask`, while inline runs
/// surface as an `AgentMessage`.
final class AgentRunMode {
  const AgentRunMode._(this._value, [this._runInBackground]);

  static const String _messageValue = 'message';
  static const String _taskValue = 'task';
  static const String _dynamicValue = 'dynamic';

  final String _value;
  final RunInBackgroundCallback? _runInBackground;

  /// Disallows background responses.
  ///
  /// Equivalent to configuring `AgentRunOptions.allowBackgroundResponses` as
  /// `false`. In A2A terms, responses are returned as an `AgentMessage`.
  static const AgentRunMode disallowBackground = AgentRunMode._(_messageValue);

  /// Allows background responses when the agent supports them.
  ///
  /// Equivalent to configuring `AgentRunOptions.allowBackgroundResponses` as
  /// `true`. In A2A terms, responses are returned as an `AgentTask` when the
  /// agent supports background responses, and as an `AgentMessage` otherwise.
  static const AgentRunMode allowBackgroundIfSupported = AgentRunMode._(
    _taskValue,
  );

  /// Decides the run mode dynamically via [runInBackground].
  ///
  /// The delegate receives an [A2ARunDecisionContext] describing the incoming
  /// request and returns whether the agent should run in background mode.
  static AgentRunMode allowBackgroundWhen(
    RunInBackgroundCallback runInBackground,
  ) {
    return AgentRunMode._(_dynamicValue, runInBackground);
  }

  /// Determines whether the agent response should be returned as an
  /// `AgentTask` for the given [context].
  Future<bool> shouldRunInBackground(
    A2ARunDecisionContext context, {
    CancellationToken? cancellationToken,
  }) {
    if (_value == _messageValue) {
      return Future.value(false);
    }
    if (_value == _taskValue) {
      return Future.value(true);
    }
    final runInBackground = _runInBackground;
    if (runInBackground != null) {
      return runInBackground(context, cancellationToken);
    }
    return Future.value(false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentRunMode &&
          _value == other._value &&
          identical(_runInBackground, other._runInBackground);

  @override
  int get hashCode => Object.hash(_value, identityHashCode(_runInBackground));

  @override
  String toString() => _value;
}
