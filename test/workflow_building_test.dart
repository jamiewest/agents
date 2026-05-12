import 'package:agents/src/workflows/configured_executor_binding.dart';
import 'package:agents/src/workflows/direct_edge_data.dart';
import 'package:agents/src/workflows/executor_binding_extensions.dart';
import 'package:agents/src/workflows/executor_config.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/executor_options.dart';
import 'package:agents/src/workflows/function_executor.dart';
import 'package:agents/src/workflows/stateful_executor.dart';
import 'package:agents/src/workflows/stateful_executor_options.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_builder_extensions.dart';
import 'package:agents/src/workflows/workflow_context.dart';
import 'package:test/test.dart';

void main() {
  group('FunctionExecutor', () {
    test('handles messages through callback and describes protocol', () async {
      final executor = FunctionExecutor<String, int>(
        'length',
        (input, context, cancellationToken) => input.length,
      );
      final context = CollectingWorkflowContext('length');

      final result = await executor.handle('hello', context);

      expect(result, 5);
      expect(executor.protocol.accepts(String), isTrue);
      expect(executor.protocol.produces(int), isTrue);
    });

    test('customizes protocol through configure callback', () {
      final executor = FunctionExecutor<String, int>(
        'custom',
        (input, context, cancellationToken) => input.length,
        configureProtocolCallback: (builder) => builder.acceptsAllMessages(),
      );

      expect(executor.protocol.acceptsAll, isTrue);
      expect(executor.protocol.accepts(Object), isTrue);
    });
  });

  group('FunctionStatefulExecutor', () {
    test('uses state and resets to initial state', () async {
      final executor = FunctionStatefulExecutor<int, String, int>(
        'counter',
        (input, context, state, cancellationToken) =>
            (state ?? 0) + input.length,
        options: const StatefulExecutorOptions<int>(initialState: 10),
      );
      final context = CollectingWorkflowContext('counter');

      expect(await executor.handle('abc', context), 13);
      executor.state = 13;
      expect(await executor.reset(), isTrue);
      expect(executor.state, 10);
    });
  });

  group('ConfiguredExecutorBinding', () {
    test('wraps binding and applies option overrides', () async {
      final executor = FunctionExecutor<String, int>(
        'source',
        (input, context, cancellationToken) => input.length,
      );
      final binding = ExecutorInstanceBinding(executor).configured(
        const ExecutorConfig(
          id: 'configured-source',
          options: ExecutorOptions(supportsConcurrentSharedExecution: false),
        ),
      );

      expect(binding, isA<ConfiguredExecutorBinding>());
      expect(binding.id, 'configured-source');
      expect(binding.isSharedInstance, isTrue);
      expect(binding.supportsConcurrentSharedExecution, isFalse);
      expect(await binding.createInstance(), same(executor));
    });
  });

  group('WorkflowBuilderExtensions', () {
    test('binds function executors and configures route output', () async {
      final start = FunctionExecutor<String, int>(
        'start',
        (input, context, cancellationToken) => input.length,
      );
      final builder = WorkflowBuilder(ExecutorInstanceBinding(start));
      final end = builder.bindFunctionExecutor<int, String>(
        'end',
        (input, context, cancellationToken) => 'value:$input',
      );

      builder.routeFrom('start').to(end.id).toOutput();
      final workflow = builder.build();

      expect(workflow.reflectExecutors().map((e) => e.id), ['start', 'end']);
      expect(workflow.reflectOutputExecutors(), ['end']);
      final edge = workflow.reflectEdges().single.data as DirectEdgeData;
      expect(edge.sourceExecutorId, 'start');
      expect(edge.targetExecutorId, 'end');

      final protocol = await workflow.describeProtocol();
      expect(protocol.accepts(String), isTrue);
      expect(protocol.produces(String), isTrue);
    });

    test('switch builder adds multiple direct cases', () {
      final start = FunctionExecutor<String, int>(
        'start',
        (input, context, cancellationToken) => input.length,
      );
      final one = FunctionExecutor<int, String>(
        'one',
        (input, context, cancellationToken) => 'one',
      );
      final two = FunctionExecutor<int, String>(
        'two',
        (input, context, cancellationToken) => 'two',
      );
      final builder = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).bindExecutor(one).bindExecutor(two);

      builder
          .switchFrom('start')
          .caseTo('one', messageType: int)
          .caseTo('two', messageType: String);
      final workflow = builder.build();

      final edges = workflow
          .reflectEdges()
          .map((edge) => edge.data as DirectEdgeData)
          .toList();
      expect(edges.map((edge) => edge.targetExecutorId), ['one', 'two']);
      expect(edges.map((edge) => edge.messageType), [int, String]);
    });
  });
}
