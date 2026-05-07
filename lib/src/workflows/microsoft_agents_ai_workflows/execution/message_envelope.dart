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
}
