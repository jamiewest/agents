import 'package:extensions/system.dart';
import 'checkpoint_info.dart';
import 'run.dart';
import 'streaming_run.dart';
import 'workflow.dart';

/// Defines an execution environment for running, streaming, and resuming
/// workflows asynchronously, with optional checkpointing and run management
/// capabilities.
abstract class WorkflowExecutionEnvironment {
  /// Specifies whether Checkpointing is configured for this environment.
  bool get isCheckpointingEnabled;

  /// Initiates a streaming run of the specified workflow without sending any
  /// initial input. Note that the starting [Executor] will not be invoked until
  /// an input message is received.
  ///
  /// Returns: A ValueTask that represents the asynchronous operation. The
  /// result contains a StreamingRun Object for accessing the streamed workflow
  /// output.
  ///
  /// [workflow] The workflow to execute. Cannot be null.
  ///
  /// [sessionId] An optional identifier for the session. If null, a new
  /// identifier will be generated.
  ///
  /// [cancellationToken] A cancellation token that can be used to cancel the
  /// streaming operation.
  Future<StreamingRun> openStreaming(
    Workflow workflow, {
    String? sessionId,
    CancellationToken? cancellationToken,
  });

  /// Initiates an asynchronous streaming execution using the specified input.
  ///
  /// Remarks: The returned [StreamingRun] provides methods to observe and
  /// control the ongoing streaming execution. The operation will continue until
  /// the streaming execution is finished or cancelled.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous operation. The
  /// result contains a [StreamingRun] for managing and interacting with the
  /// streaming run.
  ///
  /// [workflow] The workflow to be executed. Must not be `null`.
  ///
  /// [input] The input message to be processed as part of the streaming run.
  ///
  /// [sessionId] An optional unique identifier for the session. If not
  /// provided, a new identifier will be generated.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  ///
  /// [TInput] A type of input accepted by the workflow. Must be non-nullable.
  Future<StreamingRun> runStreaming<TInput>(
    Workflow workflow,
    TInput input, {
    String? sessionId,
    CancellationToken? cancellationToken,
  });

  /// Resumes an asynchronous streaming execution for the specified input from a
  /// checkpoint.
  ///
  /// Remarks: If the operation is cancelled via the `cancellationToken` token,
  /// the streaming execution will be terminated.
  ///
  /// Returns: A [StreamingRun] that provides access to the results of the
  /// streaming run.
  ///
  /// [workflow] The workflow to be executed. Must not be `null`.
  ///
  /// [fromCheckpoint] The [CheckpointInfo] corresponding to the checkpoint from
  /// which to resume.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<StreamingRun> resumeStreaming(
    Workflow workflow,
    CheckpointInfo fromCheckpoint, {
    CancellationToken? cancellationToken,
  });

  /// Initiates a non-streaming execution of the workflow with the specified
  /// input.
  ///
  /// Remarks: The workflow will run until its first halt, and the returned
  /// [Run] will capture all outgoing events. Use the `Run` instance to resume
  /// execution with responses to outgoing events.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous operation. The
  /// result contains a [Run] for managing and interacting with the streaming
  /// run.
  ///
  /// [workflow] The workflow to be executed. Must not be `null`.
  ///
  /// [input] The input message to be processed as part of the run.
  ///
  /// [sessionId] An optional unique identifier for the session. If not
  /// provided, a new identifier will be generated.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  ///
  /// [TInput] The type of input accepted by the workflow. Must be non-nullable.
  Future<Run> run<TInput>(
    Workflow workflow,
    TInput input, {
    String? sessionId,
    CancellationToken? cancellationToken,
  });

  /// Resumes a non-streaming execution of the workflow from a checkpoint.
  ///
  /// Remarks: The workflow will run until its first halt, and the returned
  /// [Run] will capture all outgoing events. Use the `Run` instance to resume
  /// execution with responses to outgoing events.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous operation. The
  /// result contains a [Run] for managing and interacting with the streaming
  /// run.
  ///
  /// [workflow] The workflow to be executed. Must not be `null`.
  ///
  /// [fromCheckpoint] The [CheckpointInfo] corresponding to the checkpoint from
  /// which to resume.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<Run> resume(
    Workflow workflow,
    CheckpointInfo fromCheckpoint, {
    CancellationToken? cancellationToken,
  });
}
