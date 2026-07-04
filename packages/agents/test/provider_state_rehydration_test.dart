import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/provider_session_state.dart';
import 'package:agents/src/ai/harness/agent_mode/agent_mode_state.dart';
import 'package:agents/src/ai/harness/background_agents/background_agent_state.dart';
import 'package:agents/src/ai/harness/background_agents/background_task_info.dart';
import 'package:agents/src/ai/harness/background_agents/background_task_status.dart';
import 'package:agents/src/ai/harness/file_memory/file_memory_state.dart';
import 'package:agents/src/ai/harness/todo/todo_item.dart';
import 'package:agents/src/ai/harness/todo/todo_state.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_rule.dart';
import 'package:agents/src/ai/harness/tool_approval/tool_approval_state.dart';
import 'package:agents/src/ai/text_search_provider.dart';
import 'package:test/test.dart';

void main() {
  group('Provider state rehydration through bag serialization', () {
    /// Serializes [state] into a session bag, round-trips the bag through
    /// JSON, and rehydrates the typed state via a [ProviderSessionState]
    /// configured with [rehydrator].
    T roundTrip<T>(T state, T Function(Object?) rehydrator) {
      final session = _TestSession();
      session.stateBag.setValue<T>('key', state);

      final restored = _TestSession.withBag(
        AgentSessionStateBag.deserialize(session.stateBag.serialize()),
      );

      return ProviderSessionState<T>(
        (_) => throw StateError('initializer must not run'),
        'key',
        stateRehydrator: rehydrator,
      ).getOrInitializeState(restored);
    }

    test('TodoState round-trips items and nextId', () {
      final state = TodoState()
        ..items = [
          TodoItem()
            ..id = 3
            ..title = 'write tests'
            ..description = 'for rehydration'
            ..isComplete = true,
        ]
        ..nextId = 4;

      final restored = roundTrip(state, TodoState.fromJson);

      expect(restored.nextId, 4);
      expect(restored.items.single.id, 3);
      expect(restored.items.single.title, 'write tests');
      expect(restored.items.single.description, 'for rehydration');
      expect(restored.items.single.isComplete, isTrue);
    });

    test('AgentModeState round-trips modes', () {
      final state = AgentModeState()
        ..currentMode = 'execute'
        ..previousModeForNotification = 'plan';

      final restored = roundTrip(state, AgentModeState.fromJson);

      expect(restored.currentMode, 'execute');
      expect(restored.previousModeForNotification, 'plan');
    });

    test('FileMemoryState round-trips the working folder', () {
      final state = FileMemoryState()..workingFolder = 'sessions/abc';

      final restored = roundTrip(state, FileMemoryState.fromJson);

      expect(restored.workingFolder, 'sessions/abc');
    });

    test('TextSearchProviderState round-trips recent messages', () {
      final state = TextSearchProviderState(
        recentMessagesText: ['first', 'second'],
      );

      final restored = roundTrip(state, TextSearchProviderState.fromJson);

      expect(restored.recentMessagesText, ['first', 'second']);
    });

    test('BackgroundAgentState round-trips tasks and statuses', () {
      final state = BackgroundAgentState()
        ..nextTaskId = 9
        ..tasks = [
          BackgroundTaskInfo()
            ..id = 8
            ..agentName = 'researcher'
            ..description = 'dig'
            ..status = BackgroundTaskStatus.completed
            ..resultText = 'found it',
        ];

      final restored = roundTrip(state, BackgroundAgentState.fromJson);

      expect(restored.nextTaskId, 9);
      expect(restored.tasks.single.id, 8);
      expect(restored.tasks.single.status, BackgroundTaskStatus.completed);
      expect(restored.tasks.single.resultText, 'found it');
    });

    test('ToolApprovalState round-trips standing rules only', () {
      final state = ToolApprovalState()
        ..rules = [
          ToolApprovalRule(toolName: 'search'),
          ToolApprovalRule(
            toolName: 'fetch',
            arguments: {'url': '"https://example.com"'},
          ),
        ];

      final restored = roundTrip(state, ToolApprovalState.fromJson);

      expect(restored.rules, hasLength(2));
      expect(restored.rules[0].toolName, 'search');
      expect(restored.rules[0].arguments, isNull);
      expect(restored.rules[1].toolName, 'fetch');
      expect(restored.rules[1].arguments, {'url': '"https://example.com"'});
      expect(restored.collectedApprovalResponses, isEmpty);
      expect(restored.queuedApprovalRequests, isEmpty);
    });
  });
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
  _TestSession.withBag(super.stateBag);
}
