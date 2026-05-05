import 'package:extensions/system.dart';
import '../run_status.dart';
import '../workflow_event.dart';

abstract class RunEventStream implements AsyncDisposable {
  void start();
  void signalInput();
  Future stop();
  Future<RunStatus> getStatus({CancellationToken? cancellationToken});
  Stream<WorkflowEvent> takeEventStream(
    bool blockOnPendingRequest, {
    CancellationToken? cancellationToken,
  });
}
