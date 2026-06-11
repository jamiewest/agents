import 'package:a2a/a2a.dart';
import 'package:agents/src/a2a/a2a_agent_session.dart';
import 'package:test/test.dart';

void main() {
  group('A2AAgentSession serialization', () {
    test('round-trips contextId, taskId, and taskState', () {
      // Arrange
      final session = A2AAgentSession()
        ..contextId = 'ctx-1'
        ..taskId = 'task-1'
        ..taskState = A2ATaskState.working;

      // Act
      final restored = A2AAgentSession.deserialize(session.serialize());

      // Assert
      expect(restored.contextId, 'ctx-1');
      expect(restored.taskId, 'task-1');
      expect(restored.taskState, A2ATaskState.working);
    });

    test('round-trips stateBag contents', () {
      // Arrange
      final session = A2AAgentSession()..contextId = 'ctx-2';
      session.stateBag.setValue<String>('userPreference', 'dark-mode');

      // Act
      final restored = A2AAgentSession.deserialize(session.serialize());

      // Assert
      expect(restored.stateBag.count, 1);
      expect(restored.stateBag.getValue<String>('userPreference'), 'dark-mode');
    });

    test('deserializes legacy payloads without a stateBag field', () {
      // Arrange
      const legacy = '{"contextId":"ctx-3","taskId":null,"taskState":null}';

      // Act
      final restored = A2AAgentSession.deserialize(legacy);

      // Assert
      expect(restored.contextId, 'ctx-3');
      expect(restored.stateBag.count, 0);
    });
  });
}
