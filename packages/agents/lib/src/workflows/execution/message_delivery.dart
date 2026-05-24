import 'message_envelope.dart';

/// Represents a queued message delivery.
class MessageDelivery {
  /// Creates a message delivery.
  const MessageDelivery(this.envelope);

  /// Gets the message envelope to deliver.
  final MessageEnvelope envelope;

  /// Gets the target executor identifier.
  String get targetExecutorId => envelope.targetExecutorId;

  /// Gets the source executor identifier, if known.
  String? get sourceExecutorId => envelope.sourceExecutorId;

  /// Gets the message payload.
  Object? get message => envelope.message;
}
