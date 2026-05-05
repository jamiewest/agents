import 'dart:collection';
import '../checkpointing/portable_message_envelope.dart';
import 'message_envelope.dart';

class StepContext {
  StepContext();

  final Map<String, Queue<MessageEnvelope>> queuedMessages = {};

  bool get hasMessages {
    return !this.queuedMessages.isEmpty && this.queuedMessages.values.any((messageQueue) => !messageQueue.isEmpty);
  }

  Queue<MessageEnvelope> messagesFor(String target) {
    return this.queuedMessages.getOrAdd(target, (_) => Queue<MessageEnvelope>());
  }

  Map<String, List<PortableMessageEnvelope>> exportMessages() {
    return this.queuedMessages.keys.toDictionary(
            keySelector: (identity) => identity,
            elementSelector: (identity) => this.queuedMessages[identity]
                                             .map((v) => portableMessageEnvelope(v))
                                             .toList()
        );
  }

  void importMessages(Map<String, List<PortableMessageEnvelope>> messages) {
    for (final identity in messages.keys) {
      this.queuedMessages[identity] = new(messages[identity].map(UnwrapExportedState));
    }
    /* TODO: unsupported node kind "unknown" */
    // static MessageEnvelope UnwrapExportedState(PortableMessageEnvelope es) => es.ToMessageEnvelope();
  }
}
