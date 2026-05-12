import 'package:extensions/system.dart';

import '../workflow_event.dart';

/// Context that a sub-workflow runner uses to communicate with its parent.
///
/// Implemented by [InProcessRunnerContext] so that [WorkflowHostExecutor]
/// can forward events, send messages, and yield output up to the parent
/// workflow's superstep.
abstract interface class SuperStepJoinContext {
  /// Gets whether checkpointing is enabled for this context.
  bool get checkpointingEnabled;

  /// Gets whether concurrent runs are enabled for this context.
  bool get concurrentRunsEnabled;

  /// Forwards [workflowEvent] to the parent event sink.
  Future<void> forwardWorkflowEventAsync(
    WorkflowEvent workflowEvent, {
    CancellationToken? cancellationToken,
  });

  /// Sends [message] from [senderId] into the parent routing system.
  Future<void> sendMessageAsync<TMessage extends Object>(
    String senderId,
    TMessage message, {
    CancellationToken? cancellationToken,
  });

  /// Yields [output] from [senderId] as parent workflow output.
  Future<void> yieldOutputAsync<TOutput extends Object>(
    String senderId,
    TOutput output, {
    CancellationToken? cancellationToken,
  });

  /// Attaches a sub-workflow runner to this context.
  ///
  /// Returns a join identifier that can be passed to [detachSuperstepAsync].
  Future<String> attachSuperstepAsync(
    ISuperStepRunner superStepRunner, {
    CancellationToken? cancellationToken,
  });

  /// Detaches the sub-workflow runner identified by [joinId].
  Future<bool> detachSuperstepAsync(String joinId);
}

/// Minimal interface for a runner that participates in a superstep.
abstract interface class ISuperStepRunner {
  /// Gets the session identifier.
  String get sessionId;

  /// Gets whether this runner has unprocessed messages.
  bool get hasUnprocessedMessages;

  /// Gets whether this runner has unserviced external requests.
  bool get hasUnservicedRequests;

  /// Executes one superstep. Returns `true` if work was done.
  Future<bool> runSuperStepAsync({CancellationToken? cancellationToken});
}
