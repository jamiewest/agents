import 'package:extensions/system.dart';
import '../checkpoint_info.dart';
import '../checkpoint_manager.dart';
import '../execution/async_run_handle.dart';
import '../execution/execution_mode.dart';
import '../run.dart';
import '../streaming_run.dart';
import '../turn_token.dart';
import '../workflow.dart';
import '../workflow_execution_environment.dart';
import '../workflow_session.dart';
import 'in_process_runner.dart';

/// Provides an in-process implementation of the workflow execution
/// environment for running, streaming, and checkpointing workflows within the
/// current application domain.
class InProcessExecutionEnvironment implements WorkflowExecutionEnvironment {
  InProcessExecutionEnvironment(
    ExecutionMode mode,
    {bool? enableConcurrentRuns = null, CheckpointManager? checkpointManager = null, }
  ) {
    this.executionMode = mode;
    this.enableConcurrentRuns = enableConcurrentRuns;
    this.checkpointManager = checkpointManager;
  }

  late final ExecutionMode executionMode;

  late final bool enableConcurrentRuns;

  late final CheckpointManager? checkpointManager;

  /// Configure a new execution environment, inheriting configuration for the
  /// current one with the specified [CheckpointManager] for use in
  /// checkpointing.
  ///
  /// Returns: A new InProcess [WorkflowExecutionEnvironment] configured for
  /// checkpointing, inheriting configuration from the current environment.
  ///
  /// [checkpointManager] The CheckpointManager to use for checkpointing.
  InProcessExecutionEnvironment withCheckpointing(CheckpointManager? checkpointManager) {
    return new(this.executionMode, this.enableConcurrentRuns, checkpointManager);
  }

  bool get isCheckpointingEnabled {
    return this.checkpointManager != null;
  }

  Future<AsyncRunHandle> beginRun(
    Workflow workflow,
    String? sessionId,
    Iterable<Type> knownValidInputTypes,
    CancellationToken cancellationToken,
  ) {
    var runner = InProcessRunner.createTopLevelRunner(
      workflow,
      this.checkpointManager,
      sessionId,
      this.enableConcurrentRuns,
      knownValidInputTypes,
    );
    return runner.beginStreamAsync(this.executionMode, cancellationToken);
  }

  Future<AsyncRunHandle> resumeRun(
    Workflow workflow,
    CheckpointInfo fromCheckpoint,
    Iterable<Type> knownValidInputTypes,
    {bool? republishPendingEvents, CancellationToken? cancellationToken, }
  ) {
    var runner = InProcessRunner.createTopLevelRunner(
      workflow,
      this.checkpointManager,
      fromCheckpoint.sessionId,
      this.enableConcurrentRuns,
      knownValidInputTypes,
    );
    return runner.resumeStreamAsync(
      this.executionMode,
      fromCheckpoint,
      republishPendingEvents,
      cancellationToken,
    );
  }

  @override
  Future<StreamingRun> openStreaming(
    Workflow workflow,
    {String? sessionId, CancellationToken? cancellationToken, }
  ) async {
    var runHandle = await this.beginRunAsync(workflow, sessionId, [], cancellationToken)
                                             ;
    return new(runHandle);
  }

  @override
  Future<StreamingRun> runStreaming<TInput>(
    Workflow workflow,
    TInput input,
    {String? sessionId, CancellationToken? cancellationToken, }
  ) async {
    var runHandle = await this.beginRunAsync(workflow, sessionId, [], cancellationToken)
                                             ;
    return await runHandle.enqueueAndStreamAsync(input, cancellationToken);
  }

  void verifyCheckpointingConfigured() {
    if (this.checkpointManager == null) {
      throw StateError("Checkpointing is! configured for this execution environment. Please use the InProcessExecutionEnvironment.withCheckpointing method to attach a checkpointManager.");
    }
  }

  @override
  Future<StreamingRun> resumeStreaming(
    Workflow workflow,
    CheckpointInfo fromCheckpoint,
    {CancellationToken? cancellationToken, }
  ) async {
    this.verifyCheckpointingConfigured();
    var runHandle = await this.resumeRunAsync(workflow, fromCheckpoint, [], cancellationToken)
                                             ;
    return new(runHandle);
  }

  /// Resumes a streaming workflow run from a checkpoint with control over
  /// whether pending request events are republished through the event stream.
  ///
  /// [workflow] The workflow to resume.
  ///
  /// [fromCheckpoint] The checkpoint to resume from.
  ///
  /// [republishPendingEvents] When `true`, any pending request events are
  /// republished through the event stream after subscribing. When `false`, the
  /// caller is responsible for handling pending requests (e.g.,
  /// [WorkflowSession] already sends responses).
  ///
  /// [cancellationToken] Cancellation token.
  Future<StreamingRun> resumeStreamingInternal(
    Workflow workflow,
    CheckpointInfo fromCheckpoint,
    bool republishPendingEvents,
    {CancellationToken? cancellationToken, }
  ) async {
    this.verifyCheckpointingConfigured();
    var runHandle = await this.resumeRunAsync(
      workflow,
      fromCheckpoint,
      [],
      republishPendingEvents,
      cancellationToken,
    )
                                             ;
    return new(runHandle);
  }

  Future<AsyncRunHandle> beginRunHandlingChatProtocol<TInput>(
    Workflow workflow,
    TInput input,
    {String? sessionId, CancellationToken? cancellationToken, }
  ) async {
    var descriptor = await workflow.describeProtocolAsync(cancellationToken);
    var runHandle = await this.beginRunAsync(
      workflow,
      sessionId,
      descriptor.accepts,
      cancellationToken,
    )
                                             ;
    await runHandle.enqueueMessageAsync(input, cancellationToken);
    if (descriptor.isChatProtocol() && input is! TurnToken) {
      await runHandle.enqueueMessageAsync(
        turnToken(emitEvents: true),
        cancellationToken,
      ) ;
    }
    return runHandle;
  }

  @override
  Future<Run> run<TInput>(
    Workflow workflow,
    TInput input,
    {String? sessionId, CancellationToken? cancellationToken, }
  ) async {
    var runHandle = await this.beginRunHandlingChatProtocolAsync(
                                                workflow,
                                                input,
                                                sessionId,
                                                cancellationToken)
                                             ;
    var run = new(runHandle);
    await run.runToNextHaltAsync(cancellationToken);
    return run;
  }

  @override
  Future<Run> resume(
    Workflow workflow,
    CheckpointInfo fromCheckpoint,
    {CancellationToken? cancellationToken, }
  ) async {
    this.verifyCheckpointingConfigured();
    var runHandle = await this.resumeRunAsync(workflow, fromCheckpoint, [], cancellationToken)
                                             ;
    var run = new(runHandle);
    await run.runToNextHaltAsync(cancellationToken);
    return run;
  }
}
