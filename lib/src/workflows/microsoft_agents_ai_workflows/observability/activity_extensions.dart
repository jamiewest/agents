import '../../microsoft_agents_ai_purview/models/common/activity.dart';
import 'edge_runner_delivery_status.dart';
import 'tags.dart';
import '../../../activity_stubs.dart';
import '../../../map_extensions.dart';

extension ActivityExtensions on Activity? {
  /// Capture exception details in the activity.
///
/// Remarks: This method adds standard error tags to the activity and logs an
/// event with exception details.
///
/// [activity] The activity to capture exception details in.
///
/// [exception] The exception to capture.
void captureException(Exception exception) {
activity?.setTag(Tags.errorType, exception.runtimeType.fullName)
            .addException(exception)
            .setStatus(ActivityStatusCode.error, exception.message);
 }
void setEdgeRunnerDeliveryStatus(EdgeRunnerDeliveryStatus status) {
var delivered = status == EdgeRunnerDeliveryStatus.delivered;
activity?
            .setTag(Tags.edgeGroupDelivered, delivered)
            .setTag(Tags.edgeGroupDeliveryStatus, status.toStringValue());
 }
/// Executor processing spans are not nested, they are siblings. We use links
/// to represent the causal relationship between them.
void createSourceLinks(Map<String, String>? traceContext) {
if (activity == null|| traceContext == null) {
  return;
}
var propagationContext = Propagators.defaultTextMapPropagator.extract(
            default,
            traceContext,
            (
              carrier,
              key,
            ) => carrier.tryGetValue(key) ? [value] : <String>[]);
// Create a link to the source activity
        activity.addLink(activityLink(propagationContext.activityContext));
 }
 }
