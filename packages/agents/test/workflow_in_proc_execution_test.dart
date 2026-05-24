import 'package:agents/src/workflows/direct_edge_data.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/function_executor.dart';
import 'package:agents/src/workflows/in_proc/in_process_execution_environment.dart';
import 'package:agents/src/workflows/request_info_event.dart';
import 'package:agents/src/workflows/request_port.dart';
import 'package:agents/src/workflows/run_status.dart';
import 'package:agents/src/workflows/workflow_builder.dart';
import 'package:agents/src/workflows/workflow_builder_extensions.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:test/test.dart';

void main() {
  group('InProcExecutionEnvironment', () {
    test('runs direct edge workflow and emits output', () async {
      final start = FunctionExecutor<String, int>(
        'start',
        (input, context, cancellationToken) => input.length,
      );
      final end = FunctionExecutor<int, String>(
        'end',
        (input, context, cancellationToken) => 'length:$input',
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).bindExecutor(end).addEdge('start', 'end').addOutput('end').build();

      final run = await inProcExecution.runAsync(
        workflow,
        'hello',
        sessionId: 'run-1',
      );

      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(_outputs(run.outgoingEvents), ['length:5']);
    });

    test('routes fan-out and fan-in edges', () async {
      final start = FunctionExecutor<String, String>(
        'start',
        (input, context, cancellationToken) => input,
      );
      final left = FunctionExecutor<String, String>(
        'left',
        (input, context, cancellationToken) => 'left:$input',
      );
      final right = FunctionExecutor<String, String>(
        'right',
        (input, context, cancellationToken) => 'right:$input',
      );
      final join = FunctionExecutor<List<Object?>, String>(
        'join',
        (input, context, cancellationToken) => input.join('|'),
      );
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start))
          .bindExecutor(left)
          .bindExecutor(right)
          .bindExecutor(join)
          .addFanOutEdge('start', ['left', 'right'])
          .addFanInEdge(['left', 'right'], 'join')
          .addOutput('join')
          .build();

      final run = await inProcExecution.runAsync(workflow, 'x');

      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(_outputs(run.outgoingEvents), ['left:x|right:x']);
    });

    test('explicit context sends deliver to target executor', () async {
      final start = FunctionExecutor<String, void>('start', (
        input,
        context,
        cancellationToken,
      ) async {
        await context.sendMessage('sent:$input', targetExecutorId: 'end');
      });
      final end = FunctionExecutor<String, String>(
        'end',
        (input, context, cancellationToken) => input.toUpperCase(),
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).bindExecutor(end).addOutput('end').build();

      final run = await inProcExecution.runAsync(workflow, 'hello');

      expect(_outputs(run.outgoingEvents), ['SENT:HELLO']);
    });

    test('direct edge message type filters routed outputs', () async {
      final start = FunctionExecutor<String, int>(
        'start',
        (input, context, cancellationToken) => input.length,
      );
      final end = FunctionExecutor<int, String>(
        'end',
        (input, context, cancellationToken) => 'unreachable',
      );
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start))
          .bindExecutor(end)
          .addEdge('start', 'end', messageType: String)
          .addOutput('end')
          .build();

      final edge = workflow.reflectEdges().single.data as DirectEdgeData;
      expect(edge.messageType, String);

      final run = await inProcExecution.runAsync(workflow, 'hello');

      expect(_outputs(run.outgoingEvents), isEmpty);
    });

    test('external requests set pending request status', () async {
      const port = RequestPort<String, int?>('lookup');
      final start = FunctionExecutor<String, void>('start', (
        input,
        context,
        cancellationToken,
      ) async {
        await context.sendRequest(port, input);
      });
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start)).build();

      final run = await inProcExecution.runAsync(workflow, 'hello');

      expect(await run.getStatusAsync(), RunStatus.pendingRequests);
      final request = run.outgoingEvents.whereType<RequestInfoEvent>().single;
      expect(request.request.requestId, 'start-1');
      expect(request.request.request, 'hello');
    });

    test('stream async captures emitted events', () async {
      final start = FunctionExecutor<String, String>(
        'start',
        (input, context, cancellationToken) => 'output:$input',
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).addOutput('start').build();

      final run = await inProcExecution.streamAsync(workflow, input: 'x');

      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(_outputs(run.outgoingEvents), ['output:x']);
    });
  });
}

List<Object?> _outputs(Iterable<Object?> events) =>
    events.whereType<WorkflowOutputEvent>().map((event) => event.data).toList();
