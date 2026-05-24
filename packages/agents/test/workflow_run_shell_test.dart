import 'package:agents/src/workflows/external_request.dart';
import 'package:agents/src/workflows/external_request_context.dart';
import 'package:agents/src/workflows/request_halt_event.dart';
import 'package:agents/src/workflows/request_info_event.dart';
import 'package:agents/src/workflows/request_port.dart';
import 'package:agents/src/workflows/run.dart';
import 'package:agents/src/workflows/run_status.dart';
import 'package:agents/src/workflows/streaming_run.dart';
import 'package:agents/src/workflows/super_step_completed_event.dart';
import 'package:agents/src/workflows/super_step_completion_info.dart';
import 'package:agents/src/workflows/super_step_start_info.dart';
import 'package:agents/src/workflows/super_step_started_event.dart';
import 'package:agents/src/workflows/workflow.dart';
import 'package:agents/src/workflows/workflow_context.dart';
import 'package:agents/src/workflows/workflow_context_extensions.dart';
import 'package:agents/src/workflows/workflow_output_event.dart';
import 'package:agents/src/workflows/workflow_session.dart';
import 'package:test/test.dart';

void main() {
  group('WorkflowSession', () {
    test('uses provided session id or creates one', () {
      final workflow = Workflow('start');

      expect(
        WorkflowSession(workflow: workflow, sessionId: 'session-1').sessionId,
        'session-1',
      );
      expect(
        WorkflowSession(workflow: workflow).sessionId,
        startsWith('session-'),
      );
    });
  });

  group('Run', () {
    test('tracks outgoing and new events', () {
      final run = Run(sessionId: 'run-1', status: RunStatus.running);
      const first = WorkflowOutputEvent(executorId: 'a', data: 1);
      const second = WorkflowOutputEvent(executorId: 'b', data: 2);

      run.addEvent(first);
      run.addEvent(second);

      expect(run.outgoingEvents, [first, second]);
      expect(run.newEventCount, 2);
      expect(run.newEvents, [first, second]);
      expect(run.newEventCount, 0);
      expect(run.newEvents, isEmpty);
    });

    test('updates status for request and halt events and resumes', () async {
      const port = RequestPort<String, int>('lookup');
      final request = ExternalRequest<String, int>(
        requestId: 'request-1',
        port: port,
        request: 'abc',
      );
      var resumeCount = 0;
      final run = Run(
        sessionId: 'run-1',
        status: RunStatus.running,
        resumeCallback: (responses, cancellationToken) async {
          resumeCount++;
          expect(responses.single.response, 3);
        },
      );

      run.addEvent(RequestInfoEvent(request));
      expect(await run.getStatusAsync(), RunStatus.pendingRequests);

      await run.resumeAsync([request.createResponse(3)]);
      expect(resumeCount, 1);
      expect(await run.getStatusAsync(), RunStatus.running);

      run.addEvent(const RequestHaltEvent(reason: 'done'));
      expect(await run.getStatusAsync(), RunStatus.ended);
    });

    test('dispose is idempotent and blocks mutation', () async {
      final run = Run(sessionId: 'run-1');

      await run.disposeAsync();
      await run.disposeAsync();

      expect(await run.getStatusAsync(), RunStatus.ended);
      expect(
        () => run.addEvent(const WorkflowOutputEvent(executorId: 'x')),
        throwsStateError,
      );
    });
  });

  group('StreamingRun', () {
    test('publishes events to watchers', () async {
      final run = StreamingRun(
        sessionId: 'stream-1',
        status: RunStatus.running,
      );
      final events = <Object?>[];
      final subscription = run.watchStreamAsync().listen(events.add);
      const output = WorkflowOutputEvent(executorId: 'output', data: 'hello');

      await Future<void>.delayed(Duration.zero);
      run.addEvent(output);
      await Future<void>.delayed(Duration.zero);
      await run.disposeAsync();
      await subscription.cancel();

      expect(events, [output]);
      expect(run.outgoingEvents, [output]);
    });

    test(
      'sends messages responses and cancellation through callbacks',
      () async {
        const port = RequestPort<String, int>('lookup');
        final request = ExternalRequest<String, int>(
          requestId: 'request-1',
          port: port,
          request: 'abc',
        );
        final sentMessages = <Object?>[];
        final sentResponses = <Object?>[];
        var cancelled = false;
        final run = StreamingRun(
          sessionId: 'stream-1',
          sendMessageCallback: (message, cancellationToken) async {
            sentMessages.add(message);
            return true;
          },
          sendResponseCallback: (response, cancellationToken) async {
            sentResponses.add(response.response);
          },
          cancelCallback: () async {
            cancelled = true;
          },
        );

        expect(await run.trySendMessageAsync('hello'), isTrue);
        await run.sendResponseAsync(request.createResponse(3));
        await run.cancelRunAsync();

        expect(sentMessages, ['hello']);
        expect(sentResponses, [3]);
        expect(cancelled, isTrue);
        expect(await run.getStatusAsync(), RunStatus.ended);
      },
    );
  });

  group('ExternalRequestContext', () {
    test('completes matching request once', () async {
      const port = RequestPort<String, int>('lookup');
      final request = ExternalRequest<String, int>(
        requestId: 'request-1',
        port: port,
        request: 'abc',
      );
      final context = ExternalRequestContext(request);

      context.completeValue(3);
      final response = await context.response;

      expect(response.requestId, 'request-1');
      expect(response.response, 3);
      expect(context.isCompleted, isTrue);
      expect(() => context.completeValue(4), throwsStateError);
    });
  });

  group('SuperStep events', () {
    test('carry start and completion info', () {
      final started = SuperStepStartedEvent(
        0,
        SuperStepStartInfo(['a'], hasExternalMessages: true),
      );
      final completed = SuperStepCompletedEvent(
        0,
        SuperStepCompletionInfo(
          ['a'],
          ['b'],
          hasPendingMessages: true,
          hasPendingRequests: true,
          stateUpdated: true,
        ),
      );

      expect(started.stepNumber, 0);
      expect(started.info.sendingExecutors, ['a']);
      expect(started.info.hasExternalMessages, isTrue);
      expect(completed.info.activatedExecutors, ['a']);
      expect(completed.info.instantiatedExecutors, ['b']);
      expect(completed.info.hasPendingMessages, isTrue);
      expect(completed.info.hasPendingRequests, isTrue);
      expect(completed.info.stateUpdated, isTrue);
    });
  });

  group('WorkflowContextExtensions', () {
    test('forward to context methods', () async {
      final context = CollectingWorkflowContext('source');

      await context.sendTo('target', 'hello');
      await context.yieldValue(42);

      expect(context.sentMessages, ['hello']);
      expect(context.outputs, [42]);
    });
  });
}
