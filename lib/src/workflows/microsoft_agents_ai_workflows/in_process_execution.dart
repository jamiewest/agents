import 'package:extensions/system.dart';
import 'checkpoint_info.dart';
import 'checkpoint_manager.dart';
import 'in_proc/in_process_execution_environment.dart';
import 'run.dart';
import 'streaming_run.dart';
import 'workflow.dart';

/// Provides methods to initiate and manage in-process workflow executions,
/// supporting both streaming and non-streaming modes with asynchronous
/// operations.
class InProcessExecution {
  InProcessExecution();

  /// An InProcessExecution environment which will run SuperSteps in a
  /// background thread, streaming events they are raised.
  static final InProcessExecutionEnvironment offThread = InProcessExecutionEnvironment(ExecutionMode.OffThread);

  /// Gets an execution environment that enables concurrent, off-thread
  /// in-process execution.
  static final InProcessExecutionEnvironment concurrent = InProcessExecutionEnvironment(
    ExecutionMode.OffThread,
    enableConcurrentRuns: true,
  );

  /// An InProcesExecution environment which will run SuperSteps in the event
  /// watching thread, accumulating events during each SuperStep and streaming
  /// them each SuperStep is completed.
  static final InProcessExecutionEnvironment lockstep = InProcessExecutionEnvironment(ExecutionMode.Lockstep);

  /// An InProcessExecution environment which will not run SuperSteps directly,
  /// relying instead on the hosting workflow to run them directly, while
  /// streaming events they are raised.
  static final InProcessExecutionEnvironment subworkflow = InProcessExecutionEnvironment(ExecutionMode.Subworkflow);

  /// The default InProcess execution environment.
  static InProcessExecutionEnvironment get defaultValue {
    return offThread;
  }

  static Future<StreamingRun> openStreaming(
    Workflow workflow,
    String? sessionId,
    CancellationToken cancellationToken,
    {CheckpointManager? checkpointManager, },
  ) {
    return defaultValue.openStreamingAsync(workflow, sessionId, cancellationToken);
  }

  static Future<StreamingRun> runStreaming<TInput>(
    Workflow workflow,
    TInput input,
    String? sessionId,
    CancellationToken cancellationToken,
    {CheckpointManager? checkpointManager, },
  ) {
    return defaultValue.runStreamingAsync(workflow, input, sessionId, cancellationToken);
  }

  static Future<StreamingRun> resumeStreaming(
    Workflow workflow,
    CheckpointInfo fromCheckpoint,
    CheckpointManager checkpointManager,
    {CancellationToken? cancellationToken, },
  ) {
    return defaultValue.withCheckpointing(checkpointManager).resumeStreamingAsync(workflow, fromCheckpoint, cancellationToken);
  }

  static Future<Run> run<TInput>(
    Workflow workflow,
    TInput input,
    String? sessionId,
    CancellationToken cancellationToken,
    {CheckpointManager? checkpointManager, },
  ) {
    return defaultValue.runAsync(workflow, input, sessionId, cancellationToken);
  }

  static Future<Run> resume(
    Workflow workflow,
    CheckpointInfo fromCheckpoint,
    CheckpointManager checkpointManager,
    {CancellationToken? cancellationToken, },
  ) {
    return defaultValue.withCheckpointing(checkpointManager).resumeAsync(workflow, fromCheckpoint, cancellationToken);
  }
}
