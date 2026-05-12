import 'package:extensions/system.dart';

import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';
import '../checkpointing/checkpoint.dart';
import '../checkpointing/workflow_info.dart';
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
import 'message_envelope.dart';
import 'runner_context.dart';
import 'step_context.dart';

/// Executes queued workflow messages in SuperStep order.
class SuperStepRunner {
  /// Creates a super-step runner.
  SuperStepRunner(
    this.context, {
    required this.sessionId,
    this.checkpointManager,
  });

  /// Gets the runner context.
  final RunnerContext context;

  /// Gets the session identifier.
  final String sessionId;

  /// Gets the checkpoint manager, when checkpointing is enabled.
  final CheckpointManager? checkpointManager;

  /// Gets the last checkpoint produced by this runner.
  CheckpointInfo? lastCheckpoint;

  /// Runs until no messages remain or a pending external request is emitted.
  Future<RunStatus> run(
    Object? input, {
    CancellationToken? cancellationToken,
  }) => runDeliveries([
    MessageDelivery(context.createInitialEnvelope(input)),
  ], cancellationToken: cancellationToken);

  /// Runs starting with existing [initialDeliveries].
  Future<RunStatus> runDeliveries(
    Iterable<MessageDelivery> initialDeliveries, {
    int initialStepNumber = 0,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none;
    var deliveries = List<MessageDelivery>.of(initialDeliveries);
    var stepNumber = initialStepNumber;
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
      await _createCheckpointAsync(
        stepNumber,
        next.map((delivery) => delivery.envelope),
        token,
      );
      if (hasPendingRequests) {
        return RunStatus.pendingRequests;
      }
      deliveries = next;
      stepNumber++;
    }

    return RunStatus.ended;
  }

  Future<void> _createCheckpointAsync(
    int stepNumber,
    Iterable<MessageEnvelope> pendingMessages,
    CancellationToken cancellationToken,
  ) async {
    final manager = checkpointManager;
    if (manager == null) {
      return;
    }
    cancellationToken.throwIfCancellationRequested();
    final checkpoint = Checkpoint(
      info: CheckpointInfo('$sessionId-superstep-$stepNumber'),
      sessionId: sessionId,
      superStep: stepNumber,
      workflow: WorkflowInfo.fromWorkflow(context.workflow),
      pendingMessages: pendingMessages.map((message) => message.toPortable()),
    );
    lastCheckpoint = await manager.saveCheckpointAsync(checkpoint);
  }
}
