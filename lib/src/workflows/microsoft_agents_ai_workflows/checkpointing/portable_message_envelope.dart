import '../execution/executor_identity.dart';
import '../execution/message_envelope.dart';
import '../portable_value.dart';
import 'type_id.dart';

class PortableMessageEnvelope {
  PortableMessageEnvelope({
    TypeId? messageType = null,
    ExecutorIdentity? source = null,
    PortableValue? message = null,
    String? targetId = null,
    MessageEnvelope? envelope = null,
  }) {
    this.messageType = messageType;
    this.message = message;
    this.source = source;
    this.targetId = targetId;
  }

  late final TypeId messageType;

  late final PortableValue message;

  late final ExecutorIdentity source;

  late final String? targetId;

  MessageEnvelope toMessageEnvelope() {
    return messageEnvelope(
      this.message,
      this.source,
      this.messageType,
      this.targetId,
    );
  }
}
