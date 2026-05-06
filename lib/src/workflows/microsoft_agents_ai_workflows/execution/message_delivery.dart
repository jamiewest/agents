import 'message_envelope.dart';
import '../executor.dart';

class MessageDelivery {
  MessageDelivery(
    MessageEnvelope envelope, {
    String? targetId = null,
    Executor? target = null,
  }) : envelope = envelope {
    this.targetId = targetId;
  }

  late final String? targetId;

  final MessageEnvelope envelope;

  Executor? targetCache;
}
