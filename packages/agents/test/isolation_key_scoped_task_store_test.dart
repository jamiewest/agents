import 'package:a2a/a2a.dart';
import 'package:agents/src/hosting/a2a/isolation_key_scoped_task_store.dart';
import 'package:agents/src/hosting/agent_isolation_key_provider.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  late _RecordingTaskStore inner;

  setUp(() => inner = _RecordingTaskStore());

  A2ATask task(String id, String contextId) => A2ATask()
    ..id = id
    ..contextId = contextId;

  group('IsolationKeyScopedTaskStore', () {
    test('scopes the stored id and context id', () async {
      final store = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider('tenant-a'),
      );

      await store.save(task('t1', 'c1'));

      final stored = inner.tasks.values.single;
      expect(stored.id, 'tenant-a::t1');
      expect(stored.contextId, 'tenant-a::c1');
    });

    test('does not mutate the caller\'s task', () async {
      final store = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider('tenant-a'),
      );
      final original = task('t1', 'c1');

      await store.save(original);

      expect(original.id, 't1');
      expect(original.contextId, 'c1');
    });

    test('strips the key again on load', () async {
      final store = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider('tenant-a'),
      );
      await store.save(task('t1', 'c1'));

      final loaded = await store.load('t1');

      expect(loaded, isNotNull);
      expect(loaded!.id, 't1');
      expect(loaded.contextId, 'c1');
    });

    test('isolates tasks between keys', () async {
      final storeA = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider('tenant-a'),
      );
      final storeB = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider('tenant-b'),
      );
      await storeA.save(task('t1', 'c1'));

      expect(await storeB.load('t1'), isNull);
      expect(await storeA.load('t1'), isNotNull);
    });

    test('escapes colons and backslashes in the key', () async {
      final store = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider(r'a:b\c'),
      );

      await store.save(task('t1', 'c1'));

      expect(inner.tasks.keys.single, r'a\:b\\c::t1');
    });

    test('passes identifiers through when no key is available', () async {
      final store = IsolationKeyScopedTaskStore(inner, _FixedKeyProvider(null));

      await store.save(task('t1', 'c1'));

      expect(inner.tasks.keys.single, 't1');
      expect((await store.load('t1'))!.contextId, 'c1');
    });

    test('passes identifiers through when there is no provider', () async {
      final store = IsolationKeyScopedTaskStore(inner, null);

      await store.save(task('t1', 'c1'));

      expect(inner.tasks.keys.single, 't1');
    });

    test('throws in strict mode when no key is available', () async {
      final store = IsolationKeyScopedTaskStore(
        inner,
        _FixedKeyProvider(null),
        strict: true,
      );

      await expectLater(store.save(task('t1', 'c1')), throwsStateError);
      await expectLater(store.load('t1'), throwsStateError);
    });
  });
}

class _RecordingTaskStore implements A2ATaskStore {
  final Map<String, A2ATask> tasks = {};

  @override
  Future<void> save(A2ATask data) async => tasks[data.id] = data;

  @override
  Future<A2ATask?> load(String taskId) async => tasks[taskId];
}

class _FixedKeyProvider extends AgentIsolationKeyProvider {
  _FixedKeyProvider(this.key);

  final String? key;

  @override
  Future<String?> getIsolationKey({
    CancellationToken? cancellationToken,
  }) async => key;
}
