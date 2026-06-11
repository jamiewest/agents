import 'package:agents/src/workflows/edge_id.dart';
import 'package:agents/src/workflows/execution/fan_in_edge_runner.dart';
import 'package:agents/src/workflows/execution/fan_in_edge_state.dart';
import 'package:agents/src/workflows/execution/message_envelope.dart';
import 'package:agents/src/workflows/execution/runner_state_data.dart';
import 'package:agents/src/workflows/fan_in_edge_data.dart';
import 'package:test/test.dart';

FanInEdgeData _edge() => FanInEdgeData(
  id: const EdgeId('fanin-1'),
  sourceExecutorIds: ['a', 'b'],
  targetExecutorId: 'join',
);

void main() {
  group('FanInEdgeRunner.tryRoute', () {
    test('buffers until every source has contributed', () {
      // Arrange
      final runner = FanInEdgeRunner(_edge());
      final state = RunnerStateData();

      // Act
      final first = runner.tryRoute('a', 'from-a', state);
      final second = runner.tryRoute('b', 'from-b', state);

      // Assert
      expect(first, isNull);
      expect(second, isNotNull);
      expect(second!.targetExecutorId, 'join');
      expect(second.message, ['from-a', 'from-b']);
    });

    test('ignores messages from unknown sources', () {
      // Arrange
      final runner = FanInEdgeRunner(_edge());
      final state = RunnerStateData();

      // Act
      final result = runner.tryRoute('stranger', 'noise', state);

      // Assert
      expect(result, isNull);
      expect(state.fanInStates, isEmpty);
    });

    test('keeps duplicate messages from one source in arrival order', () {
      // Arrange
      final runner = FanInEdgeRunner(_edge());
      final state = RunnerStateData();

      // Act
      runner.tryRoute('a', 'a-1', state);
      final early = runner.tryRoute('a', 'a-2', state);
      final released = runner.tryRoute('b', 'b-1', state);

      // Assert: duplicates do not trigger an early release and all
      // buffered payloads are delivered ordered by source, then arrival.
      expect(early, isNull);
      expect(released!.message, ['a-1', 'a-2', 'b-1']);
    });

    test('resets after release and works for a second round', () {
      // Arrange
      final runner = FanInEdgeRunner(_edge());
      final state = RunnerStateData();
      runner.tryRoute('a', 'round1-a', state);
      runner.tryRoute('b', 'round1-b', state);

      // Act
      final pendingAgain = runner.tryRoute('b', 'round2-b', state);
      final released = runner.tryRoute('a', 'round2-a', state);

      // Assert
      expect(pendingAgain, isNull);
      expect(released!.message, ['round2-a', 'round2-b']);
    });
  });

  group('FanInEdgeState.restore', () {
    test('continues waiting only for sources without pending envelopes', () {
      // Arrange
      final edge = _edge();
      final restored = FanInEdgeState.restore(edge, [
        const MessageEnvelope(
          sourceExecutorId: 'a',
          targetExecutorId: 'join',
          message: 'restored-a',
        ),
      ]);

      // Act
      final grouped = restored.processMessage(
        'b',
        const MessageEnvelope(
          sourceExecutorId: 'b',
          targetExecutorId: 'join',
          message: 'fresh-b',
        ),
      );

      // Assert
      expect(grouped, isNotNull);
      expect(grouped!['a']!.single.message, 'restored-a');
      expect(grouped['b']!.single.message, 'fresh-b');
    });

    test('exposes buffered envelopes through pending', () {
      // Arrange
      final state = FanInEdgeState(_edge());

      // Act
      state.processMessage(
        'a',
        const MessageEnvelope(
          sourceExecutorId: 'a',
          targetExecutorId: 'join',
          message: 'buffered',
        ),
      );

      // Assert
      expect(state.pending, hasLength(1));
      expect(state.pending.single.message, 'buffered');
    });
  });
}
