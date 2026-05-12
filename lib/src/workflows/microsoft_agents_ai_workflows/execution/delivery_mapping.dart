import '../executor.dart';
import 'message_envelope.dart';

/// Maps one or more [MessageEnvelope]s to one or more executor targets.
final class DeliveryMapping {
  /// Creates a [DeliveryMapping] from [envelopes] to [targets].
  DeliveryMapping(this._envelopes, this._targets);

  /// Convenience constructor for a single envelope and single target.
  DeliveryMapping.single(MessageEnvelope envelope, Executor<dynamic, dynamic> target)
      : this([envelope], [target]);

  final Iterable<MessageEnvelope> _envelopes;
  final Iterable<Executor<dynamic, dynamic>> _targets;

  /// Enqueues all envelope/target combinations into [queue].
  ///
  /// [queue] maps target executor ID → list of pending envelopes.
  void mapInto(Map<String, List<MessageEnvelope>> queue) {
    for (final target in _targets) {
      final targetQueue = queue.putIfAbsent(
        target.id,
        () => <MessageEnvelope>[],
      );
      for (final envelope in _envelopes) {
        targetQueue.add(envelope);
      }
    }
  }
}
