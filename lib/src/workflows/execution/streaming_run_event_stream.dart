import 'dart:async';

import '../workflow_event.dart';
import 'run_event_stream.dart';

/// A [RunEventStream] backed by a broadcast [StreamController].
///
/// All [enqueue]d events are immediately forwarded to subscribers. Suitable
/// when the workflow is driven asynchronously in the background and callers
/// observe events as they arrive.
final class StreamingRunEventStream implements RunEventStream {
  final StreamController<WorkflowEvent> _controller =
      StreamController<WorkflowEvent>.broadcast();

  @override
  Stream<WorkflowEvent> get events => _controller.stream;

  @override
  bool get isCompleted => _controller.isClosed;

  @override
  Future<void> enqueue(WorkflowEvent workflowEvent) async {
    if (!_controller.isClosed) {
      _controller.add(workflowEvent);
    }
  }

  @override
  Future<void> completeAsync() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
