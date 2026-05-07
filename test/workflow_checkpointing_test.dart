import 'dart:io';

import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpoint_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/checkpoint.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/checkpoint_manager_impl.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/checkpointing_handle.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/direct_edge_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/edge_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/executor_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/fan_in_edge_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/fan_out_edge_info.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/file_system_json_checkpoint_store.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/in_memory_checkpoint_manager.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/json_checkpoint_store.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/json_marshaller.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/json_wire_serialized_value.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/portable_message_envelope.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/session_checkpoint_cache.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/workflow_info.dart';
import 'package:test/test.dart';

void main() {
  group('Checkpoint models', () {
    test('checkpoint info round trips JSON', () {
      final createdAt = DateTime.utc(2026, 5, 7, 12);
      final info = CheckpointInfo('checkpoint-1', createdAt: createdAt);

      final clone = CheckpointInfo.fromJson(info.toJson());

      expect(clone, info);
      expect(clone.toString(), 'checkpoint-1');
    });

    test('workflow and edge info round trip JSON', () {
      final workflow = WorkflowInfo(
        startExecutorId: 'start',
        name: 'wf',
        description: 'desc',
        executors: const [
          ExecutorInfo(executorId: 'start', typeName: 'StartExecutor'),
          ExecutorInfo(executorId: 'end', supportsResetting: true),
        ],
        edges: [
          const DirectEdgeInfo(
            edgeId: 'edge-1',
            sourceExecutorId: 'start',
            targetExecutorId: 'end',
            messageType: 'String',
          ),
          FanOutEdgeInfo(
            edgeId: 'edge-2',
            sourceExecutorId: 'start',
            targetExecutorIds: ['left', 'right'],
          ),
          FanInEdgeInfo(
            edgeId: 'edge-3',
            sourceExecutorIds: ['left', 'right'],
            targetExecutorId: 'join',
          ),
        ],
        outputExecutorIds: ['end'],
      );

      final clone = WorkflowInfo.fromJson(workflow.toJson());

      expect(clone.startExecutorId, 'start');
      expect(clone.executors.map((e) => e.executorId), ['start', 'end']);
      expect(clone.edges.map((e) => e.kind), ['direct', 'fanOut', 'fanIn']);
      expect(clone.outputExecutorIds, ['end']);
      expect(
        EdgeInfo.fromJson(workflow.edges.first.toJson()),
        isA<DirectEdgeInfo>(),
      );
    });

    test('checkpoint round trips JSON-shaped payload and pending messages', () {
      final checkpoint = _checkpoint(
        payload: {
          'answer': 42,
          'items': ['a', 'b'],
        },
      );

      final clone = Checkpoint.fromJson(checkpoint.toJson());

      expect(clone.info.checkpointId, 'checkpoint-1');
      expect(clone.sessionId, 'session-1');
      expect(clone.superStep, 3);
      expect(clone.payload, {
        'answer': 42,
        'items': ['a', 'b'],
      });
      expect(clone.pendingMessages.single.targetExecutorId, 'end');
    });
  });

  group('JsonMarshaller', () {
    test('serializes maps deterministically', () {
      const marshaller = JsonMarshaller();

      expect(marshaller.serialize({'b': 2, 'a': 1}), '{"a":1,"b":2}');
    });
  });

  group('JsonCheckpointStore', () {
    test('write read list and delete checkpoints', () async {
      final store = JsonCheckpointStore();
      final checkpoint = _checkpoint();

      await store.writeCheckpointAsync(checkpoint);

      expect((await store.readCheckpointAsync('checkpoint-1'))?.payload, {
        'value': 'payload',
      });
      expect(await store.listCheckpointsAsync(sessionId: 'session-1'), [
        isA<Checkpoint>(),
      ]);
      expect(await store.deleteCheckpointAsync('checkpoint-1'), isTrue);
      expect(await store.readCheckpointAsync('checkpoint-1'), isNull);
    });
  });

  group('FileSystemJsonCheckpointStore', () {
    test('creates root and persists checkpoint files', () async {
      final root = await Directory.systemTemp.createTemp('checkpoint-store-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final store = FileSystemJsonCheckpointStore(root.path);

      await store.writeCheckpointAsync(_checkpoint());

      expect(await File('${root.path}/checkpoint-1.json').exists(), isTrue);
      expect(
        (await store.readCheckpointAsync('checkpoint-1'))?.sessionId,
        'session-1',
      );
      expect(await store.listCheckpointsAsync(), hasLength(1));
      expect(await store.deleteCheckpointAsync('checkpoint-1'), isTrue);
    });

    test('rejects unsafe checkpoint ids', () async {
      final root = await Directory.systemTemp.createTemp('checkpoint-store-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final store = FileSystemJsonCheckpointStore(root.path);

      expect(
        () => store.readCheckpointAsync('../bad'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Checkpoint managers', () {
    test('manager saves payload checkpoints and restores payloads', () async {
      final store = JsonCheckpointStore();
      final manager = CheckpointManagerImpl(store, sessionId: 'session-2');

      final info = await manager.saveCheckpointAsync({'x': 1});

      expect(info.checkpointId, 'checkpoint-1');
      expect(await manager.restoreCheckpointAsync(info), {'x': 1});
      expect(
        (await store.readCheckpointAsync(info.checkpointId))?.sessionId,
        'session-2',
      );
    });

    test('in-memory manager exposes concrete json store', () async {
      final manager = InMemoryCheckpointManager(sessionId: 'session-3');

      final info = await manager.saveCheckpointAsync('payload');

      expect(manager.jsonStore.documents, contains(info.checkpointId));
      expect(await manager.restoreCheckpointAsync(info), 'payload');
    });

    test('checkpointing handle tracks current checkpoint', () async {
      final handle = CheckpointingHandle(InMemoryCheckpointManager());

      final info = await handle.checkpointAsync({'value': true});

      expect(handle.currentCheckpoint, info);
      expect(await handle.restoreAsync(), {'value': true});
    });
  });

  group('SessionCheckpointCache', () {
    test('tracks latest and lists checkpoints per session', () {
      final cache = SessionCheckpointCache();
      final first = CheckpointInfo('first');
      final second = CheckpointInfo('second');

      cache.addCheckpoint('session-1', first);
      cache.addCheckpoint('session-1', second);

      expect(cache.getLatestCheckpoint('session-1'), second);
      expect(cache.listCheckpoints('session-1'), [first, second]);
      cache.clearSession('session-1');
      expect(cache.listCheckpoints('session-1'), isEmpty);
    });
  });
}

Checkpoint _checkpoint({Object? payload = const {'value': 'payload'}}) =>
    Checkpoint(
      info: CheckpointInfo(
        'checkpoint-1',
        createdAt: DateTime.utc(2026, 5, 7, 12),
      ),
      sessionId: 'session-1',
      superStep: 3,
      workflow: WorkflowInfo(
        startExecutorId: 'start',
        executors: const [ExecutorInfo(executorId: 'start')],
        outputExecutorIds: const ['end'],
      ),
      payload: payload,
      pendingMessages: const [
        PortableMessageEnvelope(
          sourceExecutorId: 'start',
          targetExecutorId: 'end',
          message: JsonWireSerializedValue(value: 'hello', typeId: 'String'),
        ),
      ],
    );
