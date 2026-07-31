import 'dart:async';

import 'package:agents/src/workflows/direct_edge_data.dart';
import 'package:agents/src/workflows/execution/async_run_handle.dart';
import 'package:agents/src/workflows/execution/execution_mode.dart';
import 'package:agents/src/workflows/executor_instance_binding.dart';
import 'package:agents/src/workflows/external_response.dart';
import 'package:agents/src/workflows/function_executor.dart';
import 'package:agents/src/workflows/in_proc/in_process_execution_environment.dart';
import 'package:agents/src/workflows/in_proc/in_process_execution_options.dart';
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

    test('stream async streams events and records them on the run', () async {
      final start = FunctionExecutor<String, String>(
        'start',
        (input, context, cancellationToken) => 'output:$input',
      );
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).addOutput('start').build();

      final run = await inProcExecution.streamAsync(workflow, input: 'x');
      final events = await run.watchStreamAsync().toList();

      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(_outputs(events), ['output:x']);
      expect(_outputs(run.outgoingEvents), ['output:x']);
    });

    test('off-thread mode streams outputs while the executor runs', () async {
      final firstOutputSeen = Completer<void>();
      var handleDone = false;
      var seenWhileHandleRunning = false;
      final start = FunctionExecutor<String, String>('start', (
        input,
        context,
        cancellationToken,
      ) async {
        await context.yieldOutput('tok0');
        // Deadlocks (and times out) unless the watcher observes tok0 while
        // this handle invocation is still in flight.
        await firstOutputSeen.future.timeout(const Duration(seconds: 5));
        await context.yieldOutput('tok1');
        handleDone = true;
        return 'done';
      });
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(start),
      ).addOutput('start').build();

      final run = await inProcExecution.streamAsync(workflow, input: 'x');
      final outputs = <Object?>[];
      final done = Completer<void>();
      run.watchStreamAsync().listen((event) {
        if (event is! WorkflowOutputEvent) return;
        outputs.add(event.data);
        if (event.data == 'tok0' && !firstOutputSeen.isCompleted) {
          seenWhileHandleRunning = !handleDone;
          firstOutputSeen.complete();
        }
      }, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 10));

      expect(
        seenWhileHandleRunning,
        isTrue,
        reason: 'yielded outputs must stream during executor invocation',
      );
      expect(outputs, ['tok0', 'tok1', 'done']);
    });

    test('lockstep mode batches events per superstep', () async {
      const lockstepExecution = InProcExecutionEnvironment(
        options: InProcessExecutionOptions(
          executionMode: ExecutionMode.lockstep,
        ),
      );
      final step0Flushed = Completer<void>();
      var startHandleDone = false;
      var seenAfterHandleReturned = false;
      final start = FunctionExecutor<String, String>('start', (
        input,
        context,
        cancellationToken,
      ) async {
        await context.yieldOutput('a1');
        startHandleDone = true;
        return 'to-next';
      });
      // Deadlocks (and times out) unless superstep 0's events were flushed
      // before superstep 1 runs — i.e. batching is per superstep, not per
      // run.
      final next = FunctionExecutor<String, String>('next', (
        input,
        context,
        cancellationToken,
      ) async {
        await step0Flushed.future.timeout(const Duration(seconds: 5));
        return 'finished';
      });
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start))
          .bindExecutor(next)
          .addEdge('start', 'next')
          .addOutput('start')
          .addOutput('next')
          .build();

      final run = await lockstepExecution.streamAsync(workflow, input: 'x');
      final outputs = <Object?>[];
      final done = Completer<void>();
      run.watchStreamAsync().listen((event) {
        if (event is! WorkflowOutputEvent) return;
        outputs.add(event.data);
        if (event.data == 'a1' && !step0Flushed.isCompleted) {
          seenAfterHandleReturned = startHandleDone;
          step0Flushed.complete();
        }
      }, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 10));

      expect(
        seenAfterHandleReturned,
        isTrue,
        reason: 'lockstep events must not surface mid-invocation',
      );
      expect(outputs, ['a1', 'to-next', 'finished']);
    });

    test('sendRequest works with a non-nullable response port type', () async {
      const port = RequestPort<String, String>('review');
      final start = FunctionExecutor<String, void>('start', (
        input,
        context,
        cancellationToken,
      ) async {
        await context.sendRequest(port, 'draft:$input');
      });
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start)).build();

      final run = await inProcExecution.streamAsync(workflow, input: 'go');
      final event =
          await run.watchStreamAsync().firstWhere(
                (event) => event is RequestInfoEvent,
              )
              as RequestInfoEvent;

      expect(await run.getStatusAsync(), RunStatus.pendingRequests);
      expect(event.request.request, 'draft:go');
      expect(event.request.sourceExecutorId, 'start');
    });

    test('external responses route back to the requesting executor', () async {
      const port = RequestPort<String, String>('review');
      final askerSeen = <String>[];
      var chattyCalls = 0;
      // The decoy accepts String and is instantiated first; type-based
      // routing would deliver the reply here instead of the requester.
      final chatty = FunctionExecutor<String, String>('chatty', (
        input,
        context,
        cancellationToken,
      ) {
        chattyCalls++;
        return 'draft';
      });
      final asker = FunctionExecutor<String, void>('asker', (
        input,
        context,
        cancellationToken,
      ) async {
        if (input == 'draft') {
          await context.sendRequest(port, input);
          return;
        }
        askerSeen.add(input);
      });
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(chatty),
      ).bindExecutor(asker).addEdge('chatty', 'asker').build();

      final run = await inProcExecution.streamAsync(workflow, input: 'go');
      final event =
          await run.watchStreamAsync().firstWhere(
                (event) => event is RequestInfoEvent,
              )
              as RequestInfoEvent;
      await run.sendResponseAsync(event.request.createResponse('the answer'));

      expect(askerSeen, ['the answer']);
      expect(chattyCalls, 1);
      expect(await run.getStatusAsync(), RunStatus.ended);
    });

    test('responses with an unknown requestId fail clearly', () async {
      const port = RequestPort<String, String>('review');
      final seen = <String>[];
      final start = FunctionExecutor<String, void>('start', (
        input,
        context,
        cancellationToken,
      ) async {
        if (input == 'go') {
          await context.sendRequest(port, input);
          return;
        }
        seen.add(input);
      });
      final workflow = WorkflowBuilder(ExecutorInstanceBinding(start)).build();

      final run = await inProcExecution.streamAsync(workflow, input: 'go');
      final event =
          await run.watchStreamAsync().firstWhere(
                (event) => event is RequestInfoEvent,
              )
              as RequestInfoEvent;

      await expectLater(
        run.sendResponseAsync(
          ExternalResponse<String>(
            requestId: 'bogus',
            port: port.toDescriptor(),
            response: 'x',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('No pending external request "bogus"'),
          ),
        ),
      );

      // The run survives the bad response and still accepts the real one.
      await run.sendResponseAsync(event.request.createResponse('real'));
      expect(seen, ['real']);
      expect(await run.getStatusAsync(), RunStatus.ended);
    });
  });

  group('AsyncRunHandle', () {
    test('routes responses to the requester alongside a decoy', () async {
      const port = RequestPort<String, String>('review');
      final askerSeen = <String>[];
      final chatty = FunctionExecutor<String, String>(
        'chatty',
        (input, context, cancellationToken) => 'draft',
      );
      final asker = FunctionExecutor<String, void>('asker', (
        input,
        context,
        cancellationToken,
      ) async {
        if (input == 'draft') {
          await context.sendRequest(port, input);
          return;
        }
        askerSeen.add(input);
      });
      final workflow = WorkflowBuilder(
        ExecutorInstanceBinding(chatty),
      ).bindExecutor(asker).addEdge('chatty', 'asker').build();

      final handle = AsyncRunHandle.open<Object?>(workflow, input: 'go');
      final requestEvent = await handle.events
          .firstWhere((event) => event is RequestInfoEvent)
          .then((event) => event as RequestInfoEvent)
          .timeout(const Duration(seconds: 10));
      await handle.sendResponseAsync(
        requestEvent.request.createResponse('fixed'),
      );

      expect(askerSeen, ['fixed']);
      expect(await handle.getStatusAsync(), RunStatus.ended);
    });
  });

  group('ExternalResponse.pending', () {
    test('is legal for non-nullable types until read', () {
      const port = RequestPort<String, String>('review');
      final pending = ExternalResponse<String>.pending(
        requestId: 'r-1',
        port: port.toDescriptor(),
      );

      expect(pending.isPending, isTrue);
      expect(
        () => pending.response,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('has not arrived yet'),
          ),
        ),
      );
    });

    test('reads as null for nullable types', () {
      const port = RequestPort<String, String?>('review');
      final pending = ExternalResponse<String?>.pending(
        requestId: 'r-1',
        port: port.toDescriptor(),
      );

      expect(pending.isPending, isTrue);
      expect(pending.response, isNull);
    });
  });
}

List<Object?> _outputs(Iterable<Object?> events) =>
    events.whereType<WorkflowOutputEvent>().map((event) => event.data).toList();
