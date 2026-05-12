import 'package:agents/src/workflows/execution/state_manager.dart';
import 'package:agents/src/workflows/execution/step_tracer.dart';
import 'package:agents/src/workflows/portable_value.dart';
import 'package:agents/src/workflows/scope_key.dart';
import 'package:test/test.dart';

void main() {
  group('StateManager', () {
    group('writeState / readState', () {
      test('queued write is visible to readState before publishUpdates', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'key', 42);
        expect(sm.readState<int>('ex', null, 'key'), 42);
      });

      test('readState returns null for absent key', () {
        final sm = StateManager();
        expect(sm.readState<String>('ex', null, 'missing'), isNull);
      });

      test('readState throws on Object type parameter', () {
        final sm = StateManager();
        expect(
          () => sm.readState<Object>('ex', null, 'k'),
          throwsStateError,
        );
      });

      test('readState wraps non-T value as PortableValue when T is PortableValue',
          () {
        final sm = StateManager();
        sm.writeState('ex', null, 'key', 'hello');
        final pv = sm.readState<PortableValue>('ex', null, 'key');
        expect(pv, isA<PortableValue>());
        expect(pv!.asValue<String>(), 'hello');
      });

      test('readState throws when queued type does not match T', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'key', 'not-an-int');
        expect(
          () => sm.readState<int>('ex', null, 'key'),
          throwsStateError,
        );
      });

      test('writeState with named scope is isolated from default scope', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 1);
        sm.writeState('ex', 'named', 'k', 2);
        expect(sm.readState<int>('ex', null, 'k'), 1);
        expect(sm.readState<int>('ex', 'named', 'k'), 2);
      });
    });

    group('readKeys', () {
      test('returns empty set when no state written', () {
        final sm = StateManager();
        expect(sm.readKeys('ex'), isEmpty);
      });

      test('reflects queued writes before publish', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 1);
        sm.writeState('ex', null, 'b', 2);
        expect(sm.readKeys('ex'), {'a', 'b'});
      });

      test('excludes keys queued for deletion', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 1);
        sm.writeState('ex', null, 'b', 2);
        sm.publishUpdates();
        sm.clearState('ex', null, 'a');
        expect(sm.readKeys('ex'), {'b'});
      });
    });

    group('readOrInitState', () {
      test('calls factory and writes when key absent', () {
        final sm = StateManager();
        var callCount = 0;
        final result = sm.readOrInitState('ex', null, 'k', () {
          callCount++;
          return 99;
        });
        expect(result, 99);
        expect(callCount, 1);
        expect(sm.readState<int>('ex', null, 'k'), 99);
      });

      test('returns existing value without calling factory', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 7);
        var callCount = 0;
        final result = sm.readOrInitState('ex', null, 'k', () {
          callCount++;
          return 99;
        });
        expect(result, 7);
        expect(callCount, 0);
      });
    });

    group('publishUpdates', () {
      test('flushes queued writes to the scope', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 'value');
        sm.publishUpdates();
        // After publish the queue is cleared but state is persisted
        expect(sm.readState<String>('ex', null, 'k'), 'value');
        expect(sm.readKeys('ex'), {'k'});
      });

      test('is a no-op when queue is empty', () {
        final sm = StateManager();
        expect(() => sm.publishUpdates(), returnsNormally);
      });

      test('notifies tracer when updates are published', () {
        final sm = StateManager();
        final tracer = _CapturingTracer();
        sm.writeState('ex', null, 'k', 1);
        sm.publishUpdates(tracer);
        expect(tracer.statePublishedCount, 1);
      });

      test('does not notify tracer when queue is empty', () {
        final sm = StateManager();
        final tracer = _CapturingTracer();
        sm.publishUpdates(tracer);
        expect(tracer.statePublishedCount, 0);
      });

      test('successive writes followed by publish accumulate correctly', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 1);
        sm.publishUpdates();
        sm.writeState('ex', null, 'b', 2);
        sm.publishUpdates();
        expect(sm.readState<int>('ex', null, 'a'), 1);
        expect(sm.readState<int>('ex', null, 'b'), 2);
        expect(sm.readKeys('ex'), {'a', 'b'});
      });
    });

    group('clearState', () {
      test('queued delete hides published value until publish', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 'v');
        sm.publishUpdates();
        sm.clearState('ex', null, 'k');
        expect(sm.readState<String>('ex', null, 'k'), isNull);
        expect(sm.readKeys('ex'), isEmpty);
      });

      test('queued delete removes key permanently after publish', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 'v');
        sm.publishUpdates();
        sm.clearState('ex', null, 'k');
        sm.publishUpdates();
        expect(sm.readState<String>('ex', null, 'k'), isNull);
      });
    });

    group('clearScope', () {
      test('marks all persisted keys for deletion', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 1);
        sm.writeState('ex', null, 'b', 2);
        sm.publishUpdates();
        sm.clearScope('ex');
        expect(sm.readKeys('ex'), isEmpty);
      });

      test('also cancels any un-published writes in the same scope', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 1);
        sm.publishUpdates();
        sm.writeState('ex', null, 'b', 99);
        sm.clearScope('ex');
        expect(sm.readKeys('ex'), isEmpty);
        expect(sm.readState<int>('ex', null, 'b'), isNull);
      });

      test('does not affect other scopes', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 1);
        sm.writeState('other', null, 'b', 2);
        sm.publishUpdates();
        sm.clearScope('ex');
        expect(sm.readState<int>('other', null, 'b'), 2);
      });

      test('no-op when scope has no state', () {
        final sm = StateManager();
        expect(() => sm.clearScope('ex'), returnsNormally);
      });
    });

    group('exportState / importState', () {
      test('exportState returns all persisted key/value pairs', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'a', 42);
        sm.writeState('ex', null, 'b', 'hello');
        sm.publishUpdates();

        final exported = sm.exportState();

        final keyA = ScopeKey.fromParts('ex', null, 'a');
        final keyB = ScopeKey.fromParts('ex', null, 'b');
        expect(exported[keyA]?.asValue<int>(), 42);
        expect(exported[keyB]?.asValue<String>(), 'hello');
      });

      test('exportState throws when there are queued updates', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 1);
        expect(() => sm.exportState(), throwsStateError);
      });

      test('importState restores exported state', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'x', 'imported');
        sm.publishUpdates();
        final exported = sm.exportState();

        final fresh = StateManager();
        fresh.importState(exported);

        expect(fresh.readState<String>('ex', null, 'x'), 'imported');
        expect(fresh.readKeys('ex'), {'x'});
      });

      test('importState replaces existing state', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'old', 'gone');
        sm.publishUpdates();

        final other = StateManager();
        other.writeState('ex', null, 'new', 'here');
        other.publishUpdates();
        final newState = other.exportState();

        sm.importState(newState);
        expect(sm.readState<String>('ex', null, 'new'), 'here');
        expect(sm.readState<String>('ex', null, 'old'), isNull);
      });

      test('importState throws when there are queued updates', () {
        final sm = StateManager();
        sm.writeState('ex', null, 'k', 1);
        expect(() => sm.importState({}), throwsStateError);
      });

      test('exportState returns empty map when no state written', () {
        final sm = StateManager();
        expect(sm.exportState(), isEmpty);
      });
    });

    group('named scope semantics', () {
      test('named scope equality is by name regardless of executorId', () {
        final sm = StateManager();
        // Write via executor 'a' to named scope 'shared'
        sm.writeState('a', 'shared', 'k', 'v');
        sm.publishUpdates();
        // Read via executor 'b' with same named scope — should see the value
        expect(sm.readState<String>('b', 'shared', 'k'), 'v');
      });
    });
  });
}

class _CapturingTracer implements IStepTracer {
  int statePublishedCount = 0;

  @override
  void traceStatePublished() => statePublishedCount++;

  @override
  void traceActivated(String executorId) {}

  @override
  void traceCheckpointCreated(checkpoint) {}

  @override
  void traceInstantiated(String executorId) {}
}
