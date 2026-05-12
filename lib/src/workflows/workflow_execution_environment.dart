import 'package:extensions/system.dart';

import 'checkpoint_info.dart';
import 'checkpoint_manager.dart';
import 'run.dart';
import 'streaming_run.dart';
import 'workflow.dart';

/// Defines an execution environment for running and streaming workflows.
abstract interface class WorkflowExecutionEnvironment {
  /// Initiates a non-streaming execution of [workflow] with [input].
  Future<Run> runAsync<TInput>(
    Workflow workflow,
    TInput input, {
    CheckpointManager? checkpointManager,
    String? sessionId,
    CancellationToken? cancellationToken,
  });

  /// Initiates a streaming execution of [workflow] with optional [input].
  Future<StreamingRun> streamAsync<TInput>(
    Workflow workflow, {
    TInput? input,
    CheckpointManager? checkpointManager,
    String? sessionId,
    CancellationToken? cancellationToken,
  });

  /// Initiates a streaming run without sending initial input.
  Future<StreamingRun> openStreamAsync(
    Workflow workflow, {
    String? sessionId,
    CancellationToken? cancellationToken,
  }) => streamAsync<Object?>(
    workflow,
    sessionId: sessionId,
    cancellationToken: cancellationToken,
  );

  /// Resumes a non-streaming execution from a checkpoint.
  Future<Run> resumeAsync(
    Workflow workflow,
    CheckpointInfo checkpoint,
    CheckpointManager checkpointManager, {
    String? sessionId,
    CancellationToken? cancellationToken,
  });

  /// Resumes a streaming execution from a checkpoint.
  Future<StreamingRun> resumeStreamAsync(
    Workflow workflow,
    CheckpointInfo checkpoint,
    CheckpointManager checkpointManager, {
    String? sessionId,
    CancellationToken? cancellationToken,
  });
}
