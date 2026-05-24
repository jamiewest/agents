import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/in_proc/in_process_execution_environment.dart';
import 'package:agents/src/workflows/reflection/reflecting_executor.dart';
import 'package:agents/src/workflows/reflection/reflection_extensions.dart';
import 'package:agents/src/workflows/reflection/route_builder_extensions.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_context.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:test/test.dart';

// ── fakes ──────────────────────────────────────────────────────────────────

class _DispatchExecutor extends ReflectingExecutor {
  _DispatchExecutor() : super('dispatch');

  @override
  void configureHandlers(HandlerRegistry registry) {
    registry.on<String>((msg, ctx, ct) async => 'str:$msg');
    registry.on<int>((msg, ctx, ct) async => 'int:$msg');
  }
}

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  group('ReflectingExecutor', () {
    test('dispatches String message to correct handler', () async {
      final executor = _DispatchExecutor();
      final result = await executor.handle('hello', _noopCtx);
      expect(result, 'str:hello');
    });

    test('dispatches int message to correct handler', () async {
      final executor = _DispatchExecutor();
      final result = await executor.handle(42, _noopCtx);
      expect(result, 'int:42');
    });

    test('returns null for unregistered message type', () async {
      final executor = _DispatchExecutor();
      final result = await executor.handle(3.14, _noopCtx);
      expect(result, isNull);
    });

    test('handlerTypes contains registered types', () {
      final executor = _DispatchExecutor();
      expect(executor.handlerTypes, containsAll([String, int]));
    });

    test('canAccept returns true for registered types', () {
      final executor = _DispatchExecutor();
      expect(executor.canAccept(String), isTrue);
      expect(executor.canAccept(int), isTrue);
      expect(executor.canAccept(double), isFalse);
    });

    test('addEdgesForHandlers wires type-filtered edges', () async {
      final dispatch = _DispatchExecutor();
      final start = _PassthroughExecutor();

      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start))
          .bindReflectingExecutor(dispatch)
          .addEdgesForHandlers(start.id, dispatch)
          .addOutput(dispatch.id)
          .build();

      final edges = workflow.reflectEdges().toList();
      expect(edges, hasLength(2));
    });

    test(
      'workflow routes typed messages through reflecting executor',
      () async {
        final dispatch = _DispatchExecutor();
        final start = _PassthroughExecutor();

        final workflow = WorkflowBuilder(ExecutorInstanceBinding(start))
            .bindReflectingExecutor(dispatch)
            .addEdgesForHandlers(start.id, dispatch)
            .addOutput(dispatch.id)
            .build();

        final run = await inProcExecution.runAsync(workflow, 'world');

        final outputs = run.outgoingEvents
            .whereType<WorkflowOutputEvent>()
            .map((e) => e.data)
            .toList();
        expect(outputs, ['str:world']);
      },
    );
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

class _PassthroughExecutor extends ReflectingExecutor {
  _PassthroughExecutor() : super('start');

  @override
  void configureHandlers(HandlerRegistry registry) {
    registry.on<String>((msg, ctx, ct) async => msg);
    registry.on<int>((msg, ctx, ct) async => msg);
  }
}

final _noopCtx = CollectingWorkflowContext('test');
