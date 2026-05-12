import 'dart:convert';

import 'checkpointing/checkpoint.dart';

/// JSON serialization helpers for workflow checkpoints.
final class WorkflowsJsonUtilities {
  const WorkflowsJsonUtilities._();

  /// Serializes [checkpoint] to a compact JSON string.
  static String serializeCheckpoint(Checkpoint checkpoint) =>
      jsonEncode(checkpoint.toJson());

  /// Deserializes a [Checkpoint] from a JSON [source] string.
  static Checkpoint deserializeCheckpoint(String source) =>
      Checkpoint.fromJson(
        (jsonDecode(source) as Map).cast<String, Object?>(),
      );
}
