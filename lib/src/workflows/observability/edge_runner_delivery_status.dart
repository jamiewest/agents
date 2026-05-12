/// Describes the outcome of a message delivery attempt through an edge runner.
enum EdgeRunnerDeliveryStatus {
  /// The message was successfully delivered.
  delivered,

  /// The message was dropped due to a type mismatch.
  droppedTypeMismatch,

  /// The message was dropped because no target matched.
  droppedTargetMismatch,

  /// The message was dropped because a routing condition evaluated to false.
  droppedConditionFalse,

  /// Delivery failed with an exception.
  exception,

  /// The message was buffered for later delivery.
  buffered,
}

/// String-value helpers for [EdgeRunnerDeliveryStatus].
extension EdgeRunnerDeliveryStatusExtension on EdgeRunnerDeliveryStatus {
  /// Returns a human-readable string for the status.
  String toStringValue() => switch (this) {
        EdgeRunnerDeliveryStatus.delivered => 'delivered',
        EdgeRunnerDeliveryStatus.droppedTypeMismatch => 'dropped type mismatch',
        EdgeRunnerDeliveryStatus.droppedTargetMismatch =>
          'dropped target mismatch',
        EdgeRunnerDeliveryStatus.droppedConditionFalse =>
          'dropped condition false',
        EdgeRunnerDeliveryStatus.exception => 'exception',
        EdgeRunnerDeliveryStatus.buffered => 'buffered',
      };
}
