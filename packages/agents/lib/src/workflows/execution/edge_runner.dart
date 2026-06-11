import 'delivery_mapping.dart';
import 'message_envelope.dart';
import 'step_tracer.dart';

/// Base class for all workflow edge runners.
///
/// Concrete subclasses implement [chaseEdge] to decide which executor(s)
/// should receive a given [MessageEnvelope].
abstract class EdgeRunner {
  /// Attempts to route [envelope] and returns a [DeliveryMapping] when the
  /// edge accepts the message, or `null` when it does not apply.
  DeliveryMapping? chaseEdge(
    MessageEnvelope envelope, {
    StepTracer? stepTracer,
  });
}
