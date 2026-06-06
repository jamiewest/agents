import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

import 'a2a_ai_content_extensions.dart';

/// Extension methods for [A2ATaskStatus].
extension AgentTaskStatusExtensions on A2ATaskStatus {
  /// Returns the list of [AIContent] representing a user-input request when
  /// the task state is [A2ATaskState.inputRequired], or `null` otherwise.
  List<AIContent>? getUserInputRequests() {
    final msg = message;
    if (msg == null || state != A2ATaskState.inputRequired) return null;

    final contents = <AIContent>[];
    for (final part in msg.parts ?? <A2APart>[]) {
      final metadata = _partMetadata(part);
      final content = part.toAIContent()
        ..rawRepresentation = part
        ..additionalProperties = metadata?.toAdditionalProperties();
      contents.add(content);
    }
    return contents.isEmpty ? null : contents;
  }
}

Map<String, dynamic>? _partMetadata(A2APart part) {
  if (part is A2ATextPart) return part.metadata;
  if (part is A2AFilePart) return part.metadata;
  if (part is A2ADataPart) return part.metadata;
  return null;
}

extension on Map<String, dynamic> {
  AdditionalPropertiesDictionary toAdditionalProperties() =>
      Map<String, Object?>.from(this);
}
