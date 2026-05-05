enum EdgeRunnerDeliveryStatus { delivered,
droppedTypeMismatch,
droppedTargetMismatch,
droppedConditionFalse,
exception,
buffered }
extension EdgeRunnerDeliveryStatusExtensions on EdgeRunnerDeliveryStatus {String toStringValue() {
return status switch
        {
            EdgeRunnerDeliveryStatus.delivered => "delivered",
            EdgeRunnerDeliveryStatus.droppedTypeMismatch => "dropped type mismatch",
            EdgeRunnerDeliveryStatus.droppedTargetMismatch => "dropped target mismatch",
            EdgeRunnerDeliveryStatus.droppedConditionFalse => "dropped condition false",
            EdgeRunnerDeliveryStatus.exception => "exception",
            EdgeRunnerDeliveryStatus.buffered => "buffered",
            (_) => throw System.notImplementedException(),
        };
 }
 }
