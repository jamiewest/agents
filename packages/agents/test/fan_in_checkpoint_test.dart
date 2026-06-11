import 'package:agents/src/workflows/checkpoint_info.dart';
import 'package:agents/src/workflows/checkpointing/checkpoint.dart';
import 'package:agents/src/workflows/checkpointing/checkpoint_manager_impl.dart';
import 'package:agents/src/workflows/checkpointing/json_checkpoint_store.dart';
import 'package:agents/src/workflows/execution/message_envelope.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/function_executor.dart';
import 'package:agents/src/workflows/in_proc/in_process_execution_environment.dart';
import 'package:agents/src/workflows/in_process_execution.dart';
import 'package:agents/src/workflows/run_status.dart';
import 'package:agents/src/workflows/workflow.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_builder_extensions.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:test/test.dart';

/// Builds `start → {a, b1}`, `b1 → b2`, fan-in `{a, b2} → join` so that
/// executor `a` contributes to the fan-in one superstep before `b2` does.
Workflow _buildStaggeredFanInWorkflow() {
  final start = FunctionExecutor<String, String>(
    'start',
    (input, context, cancellationToken) => input,
  );
  final a = FunctionExecutor<String, String>(
    'a',
    (input, context, cancellationToken) => 'a:$input',
  );
  final b1 = FunctionExecutor<String, String>(
    'b1',
    (input, context, cancellationToken) => input,
  );
  final b2 = FunctionExecutor<String, String>(
    'b2',
    (input, context, cancellationToken) => 'b:$input',
  );
  final join = FunctionExecutor<List<Object?>, String>(
    'join',
    (input, context, cancellationToken) => input.join('|'),
  );
  return WorkflowBuilder(ExecutorInstanceBinding(start))
      .bindExecutor(a)
      .bindExecutor(b1)
      .bindExecutor(b2)
      .bindExecutor(join)
      .addFanOutEdge('start', ['a', 'b1'])
      .addEdge('b1', 'b2')
      .addFanInEdge(['a', 'b2'], 'join')
      .addOutput('join')
      .build();
}

List<Object?> _outputs(Iterable<Object?> events) =>
    events.whereType<WorkflowOutputEvent>().map((event) => event.data).toList();

void main() {
  group('Checkpoint fanInState serialization', () {
    test('round-trips fan-in envelopes through JSON', () {
      // Arrange
      const envelope = MessageEnvelope(
        sourceExecutorId: 'a',
        targetExecutorId: 'join',
        message: 'buffered-a',
      );
      final checkpoint = Checkpoint(
        info: CheckpointInfo('cp-1'),
        sessionId: 'session-1',
        superStep: 2,
        fanInState: {
          'fanin-edge': [envelope.toPortable()],
        },
      );

      // Act
      final clone = Checkpoint.fromJson(checkpoint.toJson());

      // Assert
      expect(clone.fanInState, hasLength(1));
      final restored = MessageEnvelope.fromPortable(
        clone.fanInState['fanin-edge']!.single,
      );
      expect(restored.sourceExecutorId, 'a');
      expect(restored.targetExecutorId, 'join');
      expect(restored.message, 'buffered-a');
    });

    test('defaults fanInState for legacy checkpoint JSON', () {
      // Arrange
      final json = Checkpoint(
        info: CheckpointInfo('cp-2'),
        sessionId: 'session-2',
      ).toJson()..remove('fanInState');

      // Act
      final clone = Checkpoint.fromJson(json);

      // Assert
      expect(clone.fanInState, isEmpty);
    });
  });

  group('fan-in checkpoint resume (in-proc engine)', () {
    test('resumes a run checkpointed while fan-in was partially '
        'satisfied', () async {
      // Arrange: run to completion, checkpointing every superstep through
      // a JSON store so all state round-trips through serialization.
      final store = JsonCheckpointStore();
      final manager = CheckpointManagerImpl(store, sessionId: 'fanin-run');
      final run = await inProcExecution.runAsync(
        _buildStaggeredFanInWorkflow(),
        'x',
        checkpointManager: manager,
        sessionId: 'fanin-run',
      );
      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(_outputs(run.outgoingEvents), ['a:x|b:x']);

      final checkpoints = await store.listCheckpointsAsync(
        sessionId: 'fanin-run',
      );
      final midFanIn = checkpoints.firstWhere(
        (checkpoint) => checkpoint.fanInState.isNotEmpty,
        orElse: () => fail('no checkpoint captured buffered fan-in state'),
      );

      // Act: resume from the mid-fan-in checkpoint in a fresh workflow.
      final resumed = await inProcExecution.resumeAsync(
        _buildStaggeredFanInWorkflow(),
        midFanIn.info,
        manager,
      );

      // Assert: the buffered contribution from `a` was restored, so the
      // fan-in fires once `b2` re-delivers and the workflow completes.
      expect(await resumed.getStatusAsync(), RunStatus.ended);
      expect(_outputs(resumed.outgoingEvents), ['a:x|b:x']);
    });
  });

  group('fan-in checkpoint resume (legacy engine)', () {
    test('resumes a run checkpointed while fan-in was partially '
        'satisfied', () async {
      // Arrange
      final store = JsonCheckpointStore();
      final manager = CheckpointManagerImpl(store, sessionId: 'fanin-legacy');
      final run = await inProcessExecution.runAsync(
        _buildStaggeredFanInWorkflow(),
        'x',
        checkpointManager: manager,
        sessionId: 'fanin-legacy',
      );
      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(_outputs(run.outgoingEvents), ['a:x|b:x']);

      final checkpoints = await store.listCheckpointsAsync(
        sessionId: 'fanin-legacy',
      );
      final midFanIn = checkpoints.firstWhere(
        (checkpoint) => checkpoint.fanInState.isNotEmpty,
        orElse: () => fail('no checkpoint captured buffered fan-in state'),
      );

      // Act
      final resumed = await inProcessExecution.resumeAsync(
        _buildStaggeredFanInWorkflow(),
        midFanIn.info,
        manager,
      );

      // Assert
      expect(await resumed.getStatusAsync(), RunStatus.ended);
      expect(_outputs(resumed.outgoingEvents), ['a:x|b:x']);
    });
  });
}
