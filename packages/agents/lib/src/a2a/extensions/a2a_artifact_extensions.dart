import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

import 'a2a_ai_content_extensions.dart';

/// Extension methods for [A2AArtifact].
extension A2AArtifactExtensions on A2AArtifact {
  /// Converts this artifact to a [ChatMessage].
  ChatMessage toChatMessage() {
    return ChatMessage(role: ChatRole.assistant, contents: toAIContents())
      ..additionalProperties = metadata?.toAdditionalProperties()
      ..rawRepresentation = this;
  }

  /// Converts this artifact's parts to a list of [AIContent].
  List<AIContent> toAIContents() => parts.map((p) => p.toAIContent()).toList();
}

extension on Map<String, dynamic> {
  AdditionalPropertiesDictionary toAdditionalProperties() =>
      Map<String, Object?>.from(this);
}
