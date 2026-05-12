import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/delayed_deserialization.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/checkpointing/type_id.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/concurrent_event_sink.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/execution_mode.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/executor_identity.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/state_update.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/step_tracer.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/execution/update_key.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/observability/edge_runner_delivery_status.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/observability/workflow_telemetry_options.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/scope_id.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/scope_key.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/subworkflow_error_event.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/portable_value.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/subworkflow_warning_event.dart';
import 'package:agents/src/workflows/microsoft_agents_ai_workflows/workflow_event.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  group('ScopeId', () {
    test('default scope (null scopeName) equals by executorId', () {
      final a = ScopeId('exec-1');
      final b = ScopeId('exec-1');
      expect(a, equals(b));
    });

    test('default scopes with different executorIds are not equal', () {
      expect(ScopeId('exec-1'), isNot(equals(ScopeId('exec-2'))));
    });

    test('named scopes equal by scopeName regardless of executorId', () {
      final a = ScopeId('exec-1', 'shared');
      final b = ScopeId('exec-2', 'shared');
      expect(a, equals(b));
    });

    test('named scopes with different scopeNames are not equal', () {
      expect(ScopeId('x', 'scope-a'), isNot(equals(ScopeId('x', 'scope-b'))));
    });

    test('named and unnamed scopes are not equal', () {
      expect(ScopeId('x', 'scope'), isNot(equals(ScopeId('x'))));
    });

    test('toString returns executor/default for unnamed scope', () {
      expect(ScopeId('exec-1').toString(), equals('exec-1/default'));
    });

    test('toString returns executor/name for named scope', () {
      expect(ScopeId('exec-1', 'myScope').toString(), equals('exec-1/myScope'));
    });

    test('equal instances have equal hashCodes', () {
      final a = ScopeId('exec-1', 'shared');
      final b = ScopeId('exec-2', 'shared');
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ---------------------------------------------------------------------------
  group('ScopeKey', () {
    test('equality requires matching ScopeId and key', () {
      final a = ScopeKey(ScopeId('e', 'scope'), 'k');
      final b = ScopeKey(ScopeId('e', 'scope'), 'k');
      expect(a, equals(b));
    });

    test('different keys are not equal', () {
      expect(
        ScopeKey(ScopeId('e', 's'), 'k1'),
        isNot(equals(ScopeKey(ScopeId('e', 's'), 'k2'))),
      );
    });

    test('fromParts produces correct value', () {
      final sk = ScopeKey.fromParts('exec', 'scope', 'myKey');
      expect(sk.scopeId.executorId, equals('exec'));
      expect(sk.scopeId.scopeName, equals('scope'));
      expect(sk.key, equals('myKey'));
    });

    test('toString is scopeId/key', () {
      final sk = ScopeKey(ScopeId('exec', 'scope'), 'k');
      expect(sk.toString(), equals('exec/scope/k'));
    });
  });

  // ---------------------------------------------------------------------------
  group('ExecutionMode', () {
    test('has three values', () {
      expect(ExecutionMode.values, hasLength(3));
    });

    test('values are offThread, lockstep, subworkflow', () {
      expect(
        ExecutionMode.values,
        containsAll([
          ExecutionMode.offThread,
          ExecutionMode.lockstep,
          ExecutionMode.subworkflow,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('ExecutorIdentity', () {
    test('none has null id', () {
      expect(ExecutorIdentity.none.id, isNull);
    });

    test('none equals none', () {
      expect(ExecutorIdentity.none, equals(ExecutorIdentity.none));
    });

    test('equality is case-insensitive', () {
      expect(ExecutorIdentity('Abc'), equals(ExecutorIdentity('abc')));
    });

    test('unequal when ids differ', () {
      expect(ExecutorIdentity('a'), isNot(equals(ExecutorIdentity('b'))));
    });

    test('none does not equal an identity with id', () {
      expect(ExecutorIdentity.none, isNot(equals(ExecutorIdentity('x'))));
    });

    test('toString is empty string for none', () {
      expect(ExecutorIdentity.none.toString(), isEmpty);
    });

    test('toString returns the id', () {
      expect(ExecutorIdentity('myId').toString(), equals('myId'));
    });
  });

  // ---------------------------------------------------------------------------
  group('StateUpdate', () {
    test('update with non-null value is not a delete', () {
      final u = StateUpdate.update('key', 42);
      expect(u.key, equals('key'));
      expect(u.value, equals(42));
      expect(u.isDelete, isFalse);
    });

    test('update with null value is a delete', () {
      final u = StateUpdate.update<String>('key', null);
      expect(u.isDelete, isTrue);
      expect(u.value, isNull);
    });

    test('delete creates a delete update', () {
      final u = StateUpdate.delete('key');
      expect(u.isDelete, isTrue);
      expect(u.key, equals('key'));
      expect(u.value, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('UpdateKey', () {
    test('equality requires identical executorId, scopeName, and key', () {
      final a = UpdateKey.fromParts('exec', 'scope', 'k');
      final b = UpdateKey.fromParts('exec', 'scope', 'k');
      expect(a, equals(b));
    });

    test('different executorIds are not equal', () {
      expect(
        UpdateKey.fromParts('exec-1', 'scope', 'k'),
        isNot(equals(UpdateKey.fromParts('exec-2', 'scope', 'k'))),
      );
    });

    test('isMatchingScope non-strict ignores executorId', () {
      final key = UpdateKey.fromParts('exec-1', 'shared', 'k');
      final other = ScopeId('exec-2', 'shared');
      expect(key.isMatchingScope(other), isTrue);
    });

    test('isMatchingScope strict requires executorId match', () {
      final key = UpdateKey.fromParts('exec-1', 'shared', 'k');
      final other = ScopeId('exec-2', 'shared');
      expect(key.isMatchingScope(other, strict: true), isFalse);
    });

    test('toString is scopeId/key', () {
      final key = UpdateKey.fromParts('exec', 'scope', 'k');
      expect(key.toString(), equals('exec/scope/k'));
    });
  });

  // ---------------------------------------------------------------------------
  group('ConcurrentEventSink', () {
    test('enqueue with no listener completes without error', () async {
      final sink = ConcurrentEventSink();
      await expectLater(sink.enqueue(WorkflowEvent()), completes);
    });

    test('enqueue calls eventRaised callback', () async {
      final sink = ConcurrentEventSink();
      final events = <WorkflowEvent>[];
      sink.eventRaised = (_, event) async => events.add(event);

      final ev = WorkflowEvent(data: 'hello');
      await sink.enqueue(ev);

      expect(events, hasLength(1));
      expect(events.first, same(ev));
    });

    test('implements IEventSink', () {
      expect(ConcurrentEventSink(), isA<IEventSink>());
    });
  });

  // ---------------------------------------------------------------------------
  group('IStepTracer', () {
    test('_NoOpTracer implements IStepTracer', () {
      expect(_NoOpTracer(), isA<IStepTracer>());
    });

    test('all methods can be called without error', () {
      final tracer = _NoOpTracer();
      expect(() => tracer.traceActivated('exec-1'), returnsNormally);
      expect(() => tracer.traceInstantiated('exec-1'), returnsNormally);
      expect(() => tracer.traceStatePublished(), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  group('SubworkflowErrorEvent', () {
    test('stores subworkflowId and error', () {
      final err = StateError('boom');
      final event = SubworkflowErrorEvent('sub-1', err);
      expect(event.subworkflowId, equals('sub-1'));
      expect(event.error, same(err));
    });
  });

  // ---------------------------------------------------------------------------
  group('SubworkflowWarningEvent', () {
    test('stores message and subWorkflowId', () {
      final event = SubworkflowWarningEvent('heads up', 'sub-2');
      expect(event.message, equals('heads up'));
      expect(event.subWorkflowId, equals('sub-2'));
    });
  });

  // ---------------------------------------------------------------------------
  group('EdgeRunnerDeliveryStatus', () {
    test('toStringValue returns correct strings', () {
      expect(
        EdgeRunnerDeliveryStatus.delivered.toStringValue(),
        equals('delivered'),
      );
      expect(
        EdgeRunnerDeliveryStatus.droppedTypeMismatch.toStringValue(),
        equals('dropped type mismatch'),
      );
      expect(
        EdgeRunnerDeliveryStatus.droppedTargetMismatch.toStringValue(),
        equals('dropped target mismatch'),
      );
      expect(
        EdgeRunnerDeliveryStatus.droppedConditionFalse.toStringValue(),
        equals('dropped condition false'),
      );
      expect(
        EdgeRunnerDeliveryStatus.exception.toStringValue(),
        equals('exception'),
      );
      expect(
        EdgeRunnerDeliveryStatus.buffered.toStringValue(),
        equals('buffered'),
      );
    });

    test('has six values', () {
      expect(EdgeRunnerDeliveryStatus.values, hasLength(6));
    });
  });

  // ---------------------------------------------------------------------------
  group('WorkflowTelemetryOptions', () {
    test('defaults are all false', () {
      final opts = WorkflowTelemetryOptions();
      expect(opts.enableSensitiveData, isFalse);
      expect(opts.disableWorkflowBuild, isFalse);
      expect(opts.disableWorkflowRun, isFalse);
      expect(opts.disableExecutorProcess, isFalse);
      expect(opts.disableEdgeGroupProcess, isFalse);
      expect(opts.disableMessageSend, isFalse);
      expect(opts.disableWorkflowSession, isFalse);
    });

    test('properties can be set', () {
      final opts = WorkflowTelemetryOptions()
        ..enableSensitiveData = true
        ..disableWorkflowBuild = true;
      expect(opts.enableSensitiveData, isTrue);
      expect(opts.disableWorkflowBuild, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('IDelayedDeserialization', () {
    test('stub implementation deserializes to target type', () {
      final stub = _StringDeserializer('hello');
      expect(stub.deserialize<String>(), equals('hello'));
      expect(stub.deserializeAs(String), equals('hello'));
    });

    test('deserializeAs returns null for unrecognised type', () {
      final stub = _StringDeserializer('hello');
      expect(stub.deserializeAs(int), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('PortableValue', () {
    test('constructor captures typeId from runtimeType', () {
      final pv = PortableValue(42);
      expect(pv.typeId, equals(TypeId.fromType(int)));
    });

    test('withTypeId constructor uses provided typeId', () {
      final id = TypeId('custom');
      final pv = PortableValue.withTypeId(id, 'value');
      expect(pv.typeId, equals(id));
    });

    test('asValue returns value when type matches', () {
      final pv = PortableValue('dart');
      expect(pv.asValue<String>(), equals('dart'));
    });

    test('asValue returns null when type does not match', () {
      final pv = PortableValue(99);
      expect(pv.asValue<String>(), isNull);
    });

    test('isValue returns true for matching type', () {
      final pv = PortableValue(3.14);
      expect(pv.isValue<double>(), isTrue);
    });

    test('isValue returns false for non-matching type', () {
      final pv = PortableValue(3.14);
      expect(pv.isValue<String>(), isFalse);
    });

    test('asValue deserializes lazily via IDelayedDeserialization', () {
      final lazy = _StringDeserializer('lazy-value');
      final pv = PortableValue(lazy);
      expect(pv.asValue<String>(), equals('lazy-value'));
    });

    test('asValue caches deserialized result', () {
      var callCount = 0;
      final lazy = _CountingDeserializer(() {
        callCount++;
        return 'result';
      });
      final pv = PortableValue(lazy);
      pv.asValue<String>();
      pv.asValue<String>();
      expect(callCount, equals(1));
    });

    test('asType returns value for exact runtime type', () {
      final pv = PortableValue(42);
      expect(pv.asType(int), equals(42));
    });

    test('asType returns null for different type', () {
      final pv = PortableValue(42);
      expect(pv.asType(String), isNull);
    });

    test('isType returns true for matching runtime type', () {
      final pv = PortableValue('hello');
      expect(pv.isType(String), isTrue);
    });

    test('isType returns false for non-matching type', () {
      final pv = PortableValue('hello');
      expect(pv.isType(int), isFalse);
    });

    test('asType deserializes lazily via IDelayedDeserialization', () {
      final lazy = _StringDeserializer('typed');
      final pv = PortableValue(lazy);
      expect(pv.asType(String), equals('typed'));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers

class _StringDeserializer implements IDelayedDeserialization {
  _StringDeserializer(this._value);
  final String _value;

  @override
  T deserialize<T>() => _value as T;

  @override
  Object? deserializeAs(Type targetType) =>
      targetType == String ? _value : null;
}

class _CountingDeserializer implements IDelayedDeserialization {
  _CountingDeserializer(this._factory);
  final String Function() _factory;

  @override
  T deserialize<T>() => _factory() as T;

  @override
  Object? deserializeAs(Type targetType) =>
      targetType == String ? _factory() : null;
}

class _NoOpTracer implements IStepTracer {
  @override
  void traceActivated(String executorId) {}

  @override
  void traceCheckpointCreated(checkpoint) {}

  @override
  void traceInstantiated(String executorId) {}

  @override
  void traceStatePublished() {}
}
