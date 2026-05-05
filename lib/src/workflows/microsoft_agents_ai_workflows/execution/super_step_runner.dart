import 'package:extensions/system.dart';
import '../external_response.dart';
import '../observability/workflow_telemetry_context.dart';
import '../request_info_event.dart';
import 'concurrent_event_sink.dart';

abstract class SuperStepRunner {
  String get sessionId;
  String get startExecutorId;
  WorkflowTelemetryContext get telemetryContext;
  bool get hasUnservicedRequests;
  bool get hasUnprocessedMessages;
  Future enqueueResponse(ExternalResponse response, {CancellationToken? cancellationToken, });
  (bool, String??) tryGetResponsePortExecutorId(String portId);
  Future<bool> isValidInputType<T>({CancellationToken? cancellationToken});
  Future<bool> enqueueMessage<T>(T message, {CancellationToken? cancellationToken, });
  Future<bool> enqueueMessageUntyped(
    Object message,
    Type declaredType,
    {CancellationToken? cancellationToken, },
  );
  ConcurrentEventSink get outgoingEvents;
  /// Re-emits [RequestInfoEvent]s for any pending external requests. Called by
  /// event streams after subscribing to [OutgoingEvents] so that requests
  /// restored from a checkpoint are observable even when the restore happened
  /// before the subscription was active.
  Future republishPendingEvents({CancellationToken? cancellationToken});
  Future<bool> runSuperStep(CancellationToken cancellationToken);
  Future requestEndRun();
}
