import 'message_delivery.dart';
import '../executor.dart';
import 'message_envelope.dart';
import 'step_context.dart';

class DeliveryMapping {
  DeliveryMapping({Iterable<MessageEnvelope>? envelopes = null, Iterable<Executor>? targets = null, MessageEnvelope? envelope = null, Executor? target = null, }) {
    this._envelopes = envelopes;
    this._targets = targets;
  }

  late final Iterable<MessageEnvelope> _envelopes;

  late final Iterable<Executor> _targets;

  Iterable<MessageDelivery> get deliveries {
    return from target in this._targets
                                                      from envelope in this._envelopes
                                                      select messageDelivery(envelope, target);
  }

  void mapInto(StepContext nextStep) {
    for (final target in this._targets) {
      var messageQueue = nextStep.messagesFor(target.id);
      for (final envelope in this._envelopes) {
        messageQueue.enqueue(envelope);
      }
    }
  }
}
