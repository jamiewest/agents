import 'package:extensions/system.dart';

import '../executor_completed_event.dart';
import '../executor_failed_event.dart';
import '../executor_invoked_event.dart';
import '../message_router.dart';
import '../request_info_event.dart';
import '../run_status.dart';
import '../super_step_completed_event.dart';
import '../super_step_completion_info.dart';
import '../super_step_start_info.dart';
import '../super_step_started_event.dart';
import '../workflow_error_event.dart';
import '../workflow_output_event.dart';
import 'message_delivery.dart';
import 'runner_context.dart';
import 'step_context.dart';

/// Executes queued workflow messages in SuperStep order.
class SuperStepRunner {
  /// Creates a super-step runner.
  SuperStepRunner(this.context);

  /// Gets the runner context.
  final RunnerContext context;

  /// Runs until no messages remain or a pending external request is emitted.
  Future<RunStatus> run(
    Object? input, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    var deliveries = <MessageDelivery>[
      MessageDelivery(context.createInitialEnvelope(input)),
    ];
    var stepNumber = 0;
    final router = MessageRouter(context.edgeMap, context.state);

    while (deliveries.isNotEmpty) {
      token.throwIfCancellationRequested();
      context.addEvent(
        SuperStepStartedEvent(
          stepNumber,
          SuperStepStartInfo(
            deliveries
                .map((delivery) => delivery.sourceExecutorId)
                .whereType<String>(),
          ),
        ),
      );
      final next = <MessageDelivery>[];
      final activatedExecutors = <String>[];

      for (final delivery in deliveries) {
        final executor = context.executors[delivery.targetExecutorId];
        if (executor == null) {
          throw StateError(
            'Executor "${delivery.targetExecutorId}" is not registered.',
          );
        }
        activatedExecutors.add(executor.id);
        final stepContext = StepContext(executor.id);
        context.addEvent(
          ExecutorInvokedEvent(executorId: executor.id, data: delivery.message),
        );

        Object? output;
        try {
          output = await executor.handle(
            delivery.message,
            stepContext,
            cancellationToken: token,
          );
          context.addEvent(
            ExecutorCompletedEvent(executorId: executor.id, data: output),
          );
        } catch (error) {
          context.addEvent(
            ExecutorFailedEvent(executorId: executor.id, error: error),
          );
          context.addEvent(WorkflowErrorEvent(error));
          return RunStatus.ended;
        }

        for (final yieldedOutput in stepContext.outputs) {
          context.addEvent(
            WorkflowOutputEvent(executorId: executor.id, data: yieldedOutput),
          );
        }
        for (final request in stepContext.requests) {
          context.addEvent(RequestInfoEvent(request));
        }
        next.addAll(stepContext.sentMessages.map(MessageDelivery.new));

        if (context.isOutputExecutor(executor.id) && output != null) {
          context.addEvent(
            WorkflowOutputEvent(executorId: executor.id, data: output),
          );
        }
        if (output != null) {
          next.addAll(
            router
                .route(executor.id, output)
                .map<MessageDelivery>(MessageDelivery.new),
          );
        }
      }

      final hasPendingRequests = context.events
          .whereType<RequestInfoEvent>()
          .isNotEmpty;
      context.addEvent(
        SuperStepCompletedEvent(
          stepNumber,
          SuperStepCompletionInfo(
            activatedExecutors,
            const <String>[],
            hasPendingMessages: next.isNotEmpty,
            hasPendingRequests: hasPendingRequests,
          ),
        ),
      );
      if (hasPendingRequests) {
        return RunStatus.pendingRequests;
      }
      deliveries = next;
      stepNumber++;
    }

    return RunStatus.ended;
  }
}
