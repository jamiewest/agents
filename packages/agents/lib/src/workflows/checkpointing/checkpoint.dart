import '../checkpoint_info.dart';
import 'portable_message_envelope.dart';
import 'workflow_info.dart';

/// Represents a durable workflow checkpoint.
class Checkpoint {
  /// Creates a checkpoint.
  Checkpoint({
    required this.info,
    required this.sessionId,
    this.superStep = 0,
    this.workflow,
    this.payload,
    Iterable<PortableMessageEnvelope> pendingMessages =
        const <PortableMessageEnvelope>[],
    this.properties = const <String, Object?>{},
  }) : pendingMessages = List<PortableMessageEnvelope>.unmodifiable(
         pendingMessages,
       );

  /// Gets checkpoint identity and creation info.
  final CheckpointInfo info;

  /// Gets the workflow session identifier.
  final String sessionId;

  /// Gets the super-step number represented by this checkpoint.
  final int superStep;

  /// Gets workflow definition information.
  final WorkflowInfo? workflow;

  /// Gets arbitrary checkpoint payload data.
  final Object? payload;

  /// Gets pending portable messages.
  final List<PortableMessageEnvelope> pendingMessages;

  /// Gets additional checkpoint properties.
  final Map<String, Object?> properties;

  /// Converts this checkpoint to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'info': info.toJson(),
    'sessionId': sessionId,
    'superStep': superStep,
    if (workflow != null) 'workflow': workflow!.toJson(),
    'payload': payload,
    'pendingMessages': pendingMessages
        .map((message) => message.toJson())
        .toList(),
    'properties': properties,
  };

  /// Creates a checkpoint from JSON.
  factory Checkpoint.fromJson(Map<String, Object?> json) => Checkpoint(
    info: CheckpointInfo.fromJson(
      (json['info']! as Map).cast<String, Object?>(),
    ),
    sessionId: json['sessionId']! as String,
    superStep: json['superStep'] as int? ?? 0,
    workflow: json['workflow'] == null
        ? null
        : WorkflowInfo.fromJson(
            (json['workflow']! as Map).cast<String, Object?>(),
          ),
    payload: json['payload'],
    pendingMessages: (json['pendingMessages'] as List? ?? const <Object?>[])
        .cast<Map>()
        .map(
          (value) =>
              PortableMessageEnvelope.fromJson(value.cast<String, Object?>()),
        ),
    properties: (json['properties'] as Map? ?? const <Object?, Object?>{})
        .cast<String, Object?>(),
  );
}
