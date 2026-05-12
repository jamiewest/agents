import 'package:extensions/system.dart';

import '../workflow_event.dart';
import 'run_event_stream.dart';
import 'super_step_join_context.dart';

/// A [RunEventStream] that drives one superstep at a time.
///
/// Events received via [enqueue] during a superstep are buffered, then yielded
/// in batch once [ISuperStepRunner.runSuperStepAsync] returns. The next
/// superstep is not started until the consumer has iterated all events from
/// the current one, giving the caller fine-grained control over execution
/// cadence.
///
/// Construction is two-phase: create the stream, pass it as the runner's
/// [IEventSink], then call [bindRunner] before iterating [events].
final class LockstepRunEventStream implements RunEventStream {
  final List<WorkflowEvent> _buffer = [];
  ISuperStepRunner? _runner;
  Stream<WorkflowEvent>? _stream;
  bool _completed = false;

  /// Binds the [ISuperStepRunner] that this stream will drive.
  ///
  /// Must be called before [events] is iterated. The runner must have been
  /// constructed with this instance as its outgoing event sink.
  void bindRunner(ISuperStepRunner runner) {
    assert(_runner == null, 'Runner is already bound.');
    _runner = runner;
  }

  @override
  Stream<WorkflowEvent> get events => _stream ??= _buildStream();

  @override
  bool get isCompleted => _completed;

  @override
  Future<void> enqueue(WorkflowEvent workflowEvent) async {
    _buffer.add(workflowEvent);
  }

  @override
  Future<void> completeAsync() async => _completed = true;

  Stream<WorkflowEvent> _buildStream({
    CancellationToken? cancellationToken,
  }) async* {
    final token = cancellationToken ?? CancellationToken.none;
    final runner = _runner;
    if (runner == null) {
      throw StateError(
        'LockstepRunEventStream: bindRunner() must be called before iterating '
        'events.',
      );
    }
    while (!_completed && runner.hasUnprocessedMessages) {
      token.throwIfCancellationRequested();
      _buffer.clear();
      await runner.runSuperStepAsync(cancellationToken: token);
      for (final event in List<WorkflowEvent>.of(_buffer)) {
        yield event;
      }
    }
    _completed = true;
  }
}
