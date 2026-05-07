import '../checkpointing/portable_message_envelope.dart';
import '../checkpointing/wire_marshaller.dart';

/// Wraps a workflow message with routing metadata.
class MessageEnvelope {
  /// Creates a message envelope.
  const MessageEnvelope({
    required this.targetExecutorId,
    required this.message,
    this.sourceExecutorId,
  });

  /// Gets the executor that produced the message, if known.
  final String? sourceExecutorId;

  /// Gets the executor that should receive the message.
  final String targetExecutorId;

  /// Gets the message payload.
  final Object? message;

  /// Converts this envelope to a portable checkpoint envelope.
  PortableMessageEnvelope toPortable({
    WireMarshaller wireMarshaller = const WireMarshaller(),
  }) => PortableMessageEnvelope(
    sourceExecutorId: sourceExecutorId,
    targetExecutorId: targetExecutorId,
    message: wireMarshaller.serializeValue(message),
  );

  /// Creates an envelope from a portable checkpoint envelope.
  factory MessageEnvelope.fromPortable(
    PortableMessageEnvelope envelope, {
    WireMarshaller wireMarshaller = const WireMarshaller(),
  }) => MessageEnvelope(
    sourceExecutorId: envelope.sourceExecutorId,
    targetExecutorId: envelope.targetExecutorId,
    message: wireMarshaller.deserializeValue(envelope.message),
  );
}
