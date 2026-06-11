import 'dart:convert';

import 'package:a2a/a2a.dart';

import '../abstractions/agent_session.dart';
import '../abstractions/agent_session_state_bag.dart';

/// Session for A2A-based agents.
///
/// Tracks the A2A context identifier, active task identifier, and current
/// task state across runs.
class A2AAgentSession extends AgentSession {
  A2AAgentSession._({
    this.contextId,
    this.taskId,
    this.taskState,
    AgentSessionStateBag? stateBag,
  }) : super(stateBag ?? AgentSessionStateBag(null));

  /// Creates a fresh [A2AAgentSession] with no prior conversation.
  A2AAgentSession() : super(AgentSessionStateBag(null));

  /// The context ID for the current conversation with the A2A agent.
  String? contextId;

  /// The ID of the task the agent is currently working on.
  String? taskId;

  /// The state of the task the agent is currently working on.
  A2ATaskState? taskState;

  String get debuggerDisplay =>
      'contextId=$contextId, taskId=$taskId, '
      'taskState=$taskState, stateBag=${stateBag.count}';

  /// Serializes this session to a JSON string.
  String serialize() => jsonEncode({
    'contextId': contextId,
    'taskId': taskId,
    'taskState': taskState?.name,
    'stateBag': stateBag.serialize(),
  });

  /// Creates an [A2AAgentSession] from previously serialized JSON.
  static A2AAgentSession deserialize(String serializedState) {
    final map = jsonDecode(serializedState) as Map<String, dynamic>;
    final stateValue = map['taskState'] as String?;
    return A2AAgentSession._(
      contextId: map['contextId'] as String?,
      taskId: map['taskId'] as String?,
      taskState: stateValue == null
          ? null
          : A2ATaskState.values.firstWhere(
              (s) => s.name == stateValue,
              orElse: () => A2ATaskState.unknown,
            ),
      stateBag: AgentSessionStateBag.deserialize(map['stateBag'] as String?),
    );
  }
}
