import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'checkpointable_run_base.dart';
import 'execution/async_run_handle.dart';
import 'external_response.dart';
import 'run_status.dart';
import 'workflow.dart';
import 'workflow_event.dart';

/// A [Workflow] run instance supporting a streaming form of receiving
/// workflow events, and providing a mechanism to send responses back to the
/// workflow.
class StreamingRun extends CheckpointableRunBase implements AsyncDisposable {
  StreamingRun(AsyncRunHandle runHandle) : _runHandle = runHandle {
  }

  final AsyncRunHandle _runHandle;

  /// A unique identifier for the session. Can be provided at the start of the
  /// session, or auto-generated.
  String get sessionId {
    return this._runHandle.sessionId;
  }

  /// Gets the current execution status of the workflow run.
  Future<RunStatus> getStatus({CancellationToken? cancellationToken}) {
    return this._runHandle.getStatusAsync(cancellationToken);
  }

  /// Asynchronously sends the specified response to the external system and
  /// signals completion of the current response wait operation.
  ///
  /// Remarks: The response will be queued for processing for the next
  /// superstep.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous send operation.
  ///
  /// [response] The [ExternalResponse] to send. Must not be `null`.
  Future sendResponse(ExternalResponse response) {
    return this._runHandle.enqueueResponseAsync(response);
  }

  /// Attempts to send the specified message asynchronously and returns a value
  /// indicating whether the operation was successful.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous send operation.
  /// It's [Result] is `true` if the message was sent successfully; otherwise,
  /// `false`.
  ///
  /// [message] The message instance to send. Cannot be null.
  ///
  /// [TMessage] The type of the message to send. Must be compatible with the
  /// expected message types for the starting executor, or receiving port.
  Future<bool> trySendMessage<TMessage>(TMessage message) {
    return this._runHandle.enqueueMessageAsync(message);
  }

  Future<bool> trySendMessageUntyped(Object message, {Type? declaredType, }) {
    return this._runHandle.enqueueMessageUntypedAsync(message, declaredType);
  }

  (bool, String??) tryGetResponsePortExecutorId(String portId) {
    // TODO(transpiler): implement out-param body
    throw UnimplementedError();
  }

  Stream<WorkflowEvent> watchStream({bool? blockOnPendingRequest, CancellationToken? cancellationToken, }) {
    return this._runHandle.takeEventStreamAsync(blockOnPendingRequest, cancellationToken);
  }

  /// Attempt to cancel the streaming run.
  ///
  /// Returns: A [ValueTask] that represents the asynchronous send operation.
  Future cancelRun() {
    return this._runHandle.cancelRunAsync();
  }

  @override
  Future dispose() {
    return this._runHandle.disposeAsync();
  }
}
/// Provides extension methods for processing and executing workflows using
/// streaming runs.
extension StreamingRunExtensions on StreamingRun {
  /// Processes all events from the workflow execution stream until completion.
///
/// Remarks: This method continuously monitors the workflow execution stream
/// provided by `handle` and invokes the `eventCallback` for each event. If
/// the callback returns a non-`null` response, the response is sent back to
/// the workflow using the handle.
///
/// Returns: A [ValueTask] that represents the asynchronous operation. The
/// task completes when the workflow execution stream is fully processed.
///
/// [handle] The [StreamingRun] representing the workflow execution stream to
/// monitor.
///
/// [eventCallback] An optional callback function invoked for each
/// [WorkflowEvent] received from the stream. The callback can return a
/// response Object to be sent back to the workflow, or `null` if no response
/// is required.
///
/// [cancellationToken] The [CancellationToken] to monitor for cancellation
/// requests. The default is [None].
Future runToCompletion({Func<WorkflowEvent, ExternalResponse?>? eventCallback, CancellationToken? cancellationToken, }) async  {
for (final @event in handle.watchStreamAsync(cancellationToken)) {
  var maybeResponse = eventCallback?.invoke(@event);
  if (maybeResponse != null) {
    await handle.sendResponseAsync(maybeResponse);
  }
}
 }
 }
