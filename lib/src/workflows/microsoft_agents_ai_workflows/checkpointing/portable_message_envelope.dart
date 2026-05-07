import 'json_wire_serialized_value.dart';

/// Serializable form of a workflow message envelope.
class PortableMessageEnvelope {
  /// Creates a portable message envelope.
  const PortableMessageEnvelope({
    required this.targetExecutorId,
    required this.message,
    this.sourceExecutorId,
  });

  /// Gets the source executor identifier.
  final String? sourceExecutorId;

  /// Gets the target executor identifier.
  final String targetExecutorId;

  /// Gets the serialized message.
  final JsonWireSerializedValue message;

  /// Converts this envelope to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    if (sourceExecutorId != null) 'sourceExecutorId': sourceExecutorId,
    'targetExecutorId': targetExecutorId,
    'message': message.toJson(),
  };

  /// Creates an envelope from JSON.
  factory PortableMessageEnvelope.fromJson(Map<String, Object?> json) =>
      PortableMessageEnvelope(
        sourceExecutorId: json['sourceExecutorId'] as String?,
        targetExecutorId: json['targetExecutorId']! as String,
        message: JsonWireSerializedValue.fromJson(
          (json['message']! as Map).cast<String, Object?>(),
        ),
      );
}
