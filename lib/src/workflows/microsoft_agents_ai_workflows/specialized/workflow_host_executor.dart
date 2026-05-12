import 'package:extensions/system.dart';

import '../execution/super_step_join_context.dart';
import '../executor.dart';
import '../in_proc/in_process_runner.dart';
import '../in_proc/in_process_runner_context.dart';
import '../protocol_builder.dart';
import '../resettable_executor.dart';
import '../workflow.dart';
import '../workflow_context.dart';

/// Hosts a sub-[Workflow] as an executor inside a parent workflow.
///
/// On the first [handle] call the executor creates an [InProcessRunner] for
/// the sub-workflow and attaches it to the parent superstep via
/// [SuperStepJoinContext.attachSuperstepAsync].  Subsequent calls queue
/// additional input messages.  [reset] detaches and disposes the runner.
class WorkflowHostExecutor extends Executor<Object?, Object?>
    implements ResettableExecutor {
  /// Creates a [WorkflowHostExecutor].
  WorkflowHostExecutor({required this.subWorkflow, required String id})
    : super(id);

  /// Gets the sub-workflow managed by this executor.
  final Workflow subWorkflow;

  SuperStepJoinContext? _joinContext;
  InProcessRunner? _subRunner;
  String? _joinId;
  int _sessionCounter = 0;

  @override
  void configureProtocol(ProtocolBuilder builder) {
    builder.acceptsMessage<Object?>();
  }

  @override
  Future<Object?> handle(
    Object? message,
    WorkflowContext context, {
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final joinCtx = _resolveJoinContext(context);
    final runner = await _getOrCreateRunnerAsync(
      joinCtx,
      cancellationToken: cancellationToken,
    );
    if (message != null) {
      runner.context.addExternalMessage(message);
    }
    return null;
  }

  @override
  Future<bool> reset() async {
    final runner = _subRunner;
    final joinCtx = _joinContext;
    final joinId = _joinId;
    _subRunner = null;
    _joinContext = null;
    _joinId = null;
    if (runner != null) {
      if (joinCtx != null && joinId != null) {
        await joinCtx.detachSuperstepAsync(joinId);
      }
      await runner.endRunAsync();
    }
    return true;
  }

  SuperStepJoinContext _resolveJoinContext(WorkflowContext context) {
    if (_joinContext != null) return _joinContext!;
    if (context is WorkflowStateContext) {
      return _joinContext = context.superstepJoinContext;
    }
    throw StateError(
      'WorkflowHostExecutor "$id" requires an in-process run context '
      '(WorkflowStateContext).',
    );
  }

  Future<InProcessRunner> _getOrCreateRunnerAsync(
    SuperStepJoinContext joinCtx, {
    CancellationToken? cancellationToken,
  }) async {
    if (_subRunner != null) return _subRunner!;
    final sessionId = '$id-sub-${++_sessionCounter}';
    final runner = InProcessRunner.subWorkflow(
      workflow: subWorkflow,
      sessionId: sessionId,
      parentContext: joinCtx,
    );
    _joinId = await joinCtx.attachSuperstepAsync(
      runner,
      cancellationToken: cancellationToken,
    );
    return _subRunner = runner;
  }
}
