import 'package:agents/src/workflows/direct_edge_data.dart';
import 'package:agents/src/workflows/edge_id.dart';
import 'package:agents/src/workflows/executor.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/executor_options.dart';
import 'package:agents/src/workflows/external_request.dart';
import 'package:agents/src/workflows/protocol_builder.dart';
import 'package:agents/src/workflows/request_port.dart';
import 'package:agents/src/workflows/request_port_binding.dart';
import 'package:agents/src/workflows/resettable_executor.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_context.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('ProtocolBuilder', () {
    test('builds accepted produced and request port descriptors', () {
      const port = RequestPort<String, int>('lookup');

      final protocol = ProtocolBuilder()
          .acceptsMessage<String>()
          .sendsMessage<int>()
          .requests(port)
          .build();

      expect(protocol.accepts(String), isTrue);
      expect(protocol.accepts(int), isFalse);
      expect(protocol.produces(int), isTrue);
      expect(protocol.requestPorts, [port.toDescriptor()]);
    });

    test('accepts all messages', () {
      final protocol = ProtocolBuilder().acceptsAllMessages().build();

      expect(protocol.acceptsAll, isTrue);
      expect(protocol.accepts(String), isTrue);
      expect(protocol.accepts(int), isTrue);
    });
  });

  group('ExecutorBinding', () {
    test('instance binding reflects shared executor options', () async {
      final executor = _CoreExecutor(
        'start',
        options: const ExecutorOptions(
          supportsConcurrentSharedExecution: false,
        ),
      );
      final binding = ExecutorInstanceBinding(executor);

      expect(binding.id, 'start');
      expect(binding.isSharedInstance, isTrue);
      expect(binding.supportsConcurrentSharedExecution, isFalse);
      expect(await binding.createInstance(), same(executor));
    });

    test('resettable instance binding invokes reset', () async {
      final executor = _ResettableCoreExecutor('resettable');
      final binding = ExecutorInstanceBinding(executor);

      expect(binding.supportsResetting, isTrue);
      expect(await binding.tryReset(), isTrue);
      expect(executor.resetCount, 1);
    });
  });

  group('WorkflowBuilder', () {
    test('builds workflow with executors edges outputs and ports', () async {
      const port = RequestPort<String, int>('lookup');
      final start = ExecutorInstanceBinding(_CoreExecutor('start'));
      final middle = ExecutorInstanceBinding(_CoreExecutor('middle'));
      final output = ExecutorInstanceBinding(_CoreExecutor('output'));

      final workflow = WorkflowBuilder(start)
          .withName('core')
          .withDescription('core workflow')
          .addExecutor(middle)
          .addExecutor(output)
          .addEdge('start', 'middle', messageType: int)
          .addFanOutEdge('middle', ['output'])
          .addFanInEdge(['start', 'middle'], 'output')
          .addOutput('output')
          .addRequestPort(port.toDescriptor())
          .build();

      expect(workflow.startExecutorId, 'start');
      expect(workflow.name, 'core');
      expect(workflow.description, 'core workflow');
      expect(workflow.reflectExecutors().map((e) => e.id), [
        'start',
        'middle',
        'output',
      ]);
      expect(workflow.reflectEdges(), hasLength(3));
      expect(workflow.reflectOutputExecutors(), ['output']);
      expect(workflow.reflectPorts(), [port.toDescriptor()]);

      final directEdge = workflow.reflectEdges().first.data;
      expect(directEdge, isA<DirectEdgeData>());
      expect(directEdge.id, const EdgeId('edge-1'));

      final protocol = await workflow.describeProtocol();
      expect(protocol.accepts(String), isTrue);
      expect(protocol.produces(int), isTrue);
      expect(protocol.requestPorts, contains(port.toDescriptor()));
    });

    test('rejects edges to missing executors', () {
      final builder = WorkflowBuilder(
        ExecutorInstanceBinding(_CoreExecutor('start')),
      );

      expect(() => builder.addEdge('start', 'missing'), throwsStateError);
      expect(() => builder.addOutput('missing'), throwsStateError);
    });

    test(
      'workflow ownership respects non-concurrent resettable executors',
      () async {
        final executor = _ResettableCoreExecutor(
          'start',
          options: const ExecutorOptions(
            supportsConcurrentSharedExecution: false,
            supportsResetting: true,
          ),
        );
        final workflow = WorkflowBuilder(
          ExecutorInstanceBinding(executor),
        ).addOutput('start').build();
        final owner = Object();

        expect(workflow.allowConcurrent, isFalse);
        expect(workflow.nonConcurrentExecutorIds, ['start']);
        expect(workflow.hasResettableExecutors, isTrue);

        workflow.takeOwnership(owner);
        await workflow.releaseOwnership(owner, null);

        expect(executor.resetCount, 1);
        workflow.takeOwnership(owner);
      },
    );
  });

  group('RequestPortBinding', () {
    test('invokes callback and creates paired external response', () async {
      const port = RequestPort<String, int>('lookup');
      final request = ExternalRequest<String, int>(
        requestId: 'request-1',
        port: port,
        request: 'abc',
      );
      final binding = RequestPortBinding<String, int>(
        port,
        (request) async => request.request.length,
      );

      final response = await binding.invoke(request);

      expect(response.requestId, 'request-1');
      expect(response.port, port.toDescriptor());
      expect(response.response, 3);
    });
  });

  group('WorkflowEvent', () {
    test('output event exposes payload helpers', () {
      const event = WorkflowOutputEvent(executorId: 'output', data: 42);

      expect(event.executorId, 'output');
      expect(event.isValue<int>(), isTrue);
      expect(event.isType(int), isTrue);
      expect(event.asValue<int>(), 42);
    });
  });
}

class _CoreExecutor extends Executor<Object?, Object?> {
  _CoreExecutor(super.id, {super.options});

  @override
  void configureProtocol(ProtocolBuilder builder) {
    builder.acceptsMessage<String>().sendsMessage<int>();
  }

  @override
  Future<Object?> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async => message;
}

class _ResettableCoreExecutor extends _CoreExecutor
    implements ResettableExecutor {
  _ResettableCoreExecutor(super.id, {super.options});

  int resetCount = 0;

  @override
  Future<bool> reset() async {
    resetCount++;
    return true;
  }
}
