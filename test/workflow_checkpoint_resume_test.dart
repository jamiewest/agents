import 'dart:io';

import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/file_system_json_checkpoint_store.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/in_memory_checkpoint_manager.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/checkpoint_manager_impl.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpoint_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/function_executor.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/in_process_execution.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/run_status.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_builder.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_builder_extensions.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_output_event.dart';
import 'package:test/test.dart';

void main() {
  group('checkpoint creation', () {
    test('runAsync persists checkpoints and exposes last checkpoint', () async {
      final manager = InMemoryCheckpointManager(sessionId: 'unused');
      final workflow = _twoStepWorkflow();

      final run = await inProcessExecution.runAsync(
        workflow,
        'hello',
        checkpointManager: manager,
        sessionId: 'session-1',
      );

      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(run.lastCheckpoint?.checkpointId, 'session-1-superstep-1');
      final checkpoints = await manager.jsonStore.listCheckpointsAsync(
        sessionId: 'session-1',
      );
      expect(checkpoints.map((c) => c.info.checkpointId), [
        'session-1-superstep-0',
        'session-1-superstep-1',
      ]);
      expect(checkpoints.first.pendingMessages.single.targetExecutorId, 'end');
      expect(checkpoints.first.workflow?.startExecutorId, 'start');
      expect(checkpoints.last.pendingMessages, isEmpty);
    });

    test('file-backed manager persists checkpoint documents', () async {
      final root = await Directory.systemTemp.createTemp('workflow-cp-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final store = FileSystemJsonCheckpointStore(root.path);
      final manager = CheckpointManagerImpl(store);

      await inProcessExecution.runAsync(
        _twoStepWorkflow(),
        'hello',
        checkpointManager: manager,
        sessionId: 'session-2',
      );

      expect(
        await File('${root.path}/session-2-superstep-0.json').exists(),
        isTrue,
      );
      expect(
        await store.readCheckpointAsync('session-2-superstep-0'),
        isNotNull,
      );
    });
  });

  group('checkpoint resume', () {
    test('resumeAsync continues from pending messages', () async {
      final manager = InMemoryCheckpointManager();
      final workflow = _twoStepWorkflow();
      await inProcessExecution.runAsync(
        workflow,
        'hello',
        checkpointManager: manager,
        sessionId: 'session-3',
      );
      final checkpoint = (await manager.jsonStore.readCheckpointAsync(
        'session-3-superstep-0',
      ))!;

      final resumed = await inProcessExecution.resumeAsync(
        workflow,
        checkpoint.info,
        manager,
      );

      expect(await resumed.getStatusAsync(), RunStatus.ended);
      expect(_outputs(resumed.outgoingEvents), ['length:5']);
      expect(resumed.lastCheckpoint?.checkpointId, 'session-3-superstep-1');
    });

    test('resumeStreamAsync continues from pending messages', () async {
      final manager = InMemoryCheckpointManager();
      final workflow = _twoStepWorkflow();
      await inProcessExecution.runAsync(
        workflow,
        'hi',
        checkpointManager: manager,
        sessionId: 'session-4',
      );
      final checkpoint = (await manager.jsonStore.readCheckpointAsync(
        'session-4-superstep-0',
      ))!;

      final resumed = await inProcessExecution.resumeStreamAsync(
        workflow,
        checkpoint.info,
        manager,
      );

      expect(await resumed.getStatusAsync(), RunStatus.ended);
      expect(_outputs(resumed.outgoingEvents), ['length:2']);
      expect(resumed.lastCheckpoint?.checkpointId, 'session-4-superstep-1');
    });

    test('missing checkpoint throws', () {
      final manager = InMemoryCheckpointManager();

      expect(
        () => inProcessExecution.resumeAsync(
          _twoStepWorkflow(),
          CheckpointInfo('missing-checkpoint'),
          manager,
        ),
        throwsStateError,
      );
    });
  });
}

WorkflowBuilder _twoStepBuilder() {
  final start = FunctionExecutor<String, int>(
    'start',
    (input, context, cancellationToken) => input.length,
  );
  final end = FunctionExecutor<int, String>(
    'end',
    (input, context, cancellationToken) => 'length:$input',
  );
  return WorkflowBuilder(
    ExecutorInstanceBinding(start),
  ).bindExecutor(end).addEdge('start', 'end').addOutput('end');
}

Workflow _twoStepWorkflow() => _twoStepBuilder().build();

List<Object?> _outputs(Iterable<Object?> events) =>
    events.whereType<WorkflowOutputEvent>().map((event) => event.data).toList();
