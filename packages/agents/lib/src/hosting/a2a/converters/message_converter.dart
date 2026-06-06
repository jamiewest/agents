import 'package:a2a/a2a.dart';
import 'package:extensions/ai.dart';

import '../../../a2a/extensions/a2a_ai_content_extensions.dart';
import '../../../abstractions/agent_response.dart';
import '../../../abstractions/agent_response_update.dart';

/// Converts a collection of [ChatMessage] objects to A2A [A2APart] objects.
extension ChatMessagesToPartsExtension on Iterable<ChatMessage> {
  /// Flattens the contents of every message into an ordered list of parts.
  ///
  /// Content items with no A2A representation are skipped.
  List<A2APart> toParts() {
    final parts = <A2APart>[];
    for (final message in this) {
      final messageParts = message.contents.toParts();
      if (messageParts != null) {
        parts.addAll(messageParts);
      }
    }
    return parts;
  }
}

/// Converts an [AgentResponse] to A2A [A2APart] objects.
extension AgentResponseToPartsExtension on AgentResponse {
  /// Converts the response messages to an ordered list of parts.
  List<A2APart> toParts() => messages.toParts();
}

/// Converts an [AgentResponseUpdate] to A2A [A2APart] objects.
extension AgentResponseUpdateToPartsExtension on AgentResponseUpdate {
  /// Converts the update contents to a list of parts, skipping content items
  /// with no A2A representation.
  List<A2APart> toParts() => contents.toParts() ?? <A2APart>[];
}

/// Converts an agent additional-properties dictionary to A2A metadata.
extension AdditionalPropertiesToA2AMetadataExtension
    on AdditionalPropertiesDictionary {
  /// Returns a JSON-compatible metadata map for use on A2A protocol objects.
  A2ASV toA2AMetadata() => Map<String, dynamic>.from(this);
}

/// Converts A2A metadata to an agent additional-properties dictionary.
extension A2AMetadataToAdditionalPropertiesExtension on A2ASV {
  /// Returns an additional-properties dictionary mirroring this metadata.
  AdditionalPropertiesDictionary toAdditionalProperties() =>
      Map<String, Object?>.from(this);
}
