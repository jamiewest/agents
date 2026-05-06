import 'dart:convert' as convert;
import 'package:extensions/ai.dart';
import '../../json_stubs.dart';

/// JSON serialization utilities for workflow message lists.
extension WorkflowsJsonUtilities on Iterable<ChatMessage> {
  /// Serializes this message list to a [JsonElement].
  JsonElement serialize() {
    return JsonSerializer.serializeToElement(toList());
  }
}

/// Deserialization utilities for workflow message JSON.
extension WorkflowsJsonDeserialize on JsonElement {
  /// Deserializes a [JsonElement] to a list of [ChatMessage].
  List<ChatMessage> deserializeMessages() {
    if (value is List) {
      return (value as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => ChatMessage(role: ChatRole.user, contents: m['content'] != null ? [TextContent(m['content'].toString())] : null))
          .toList();
    }
    return [];
  }
}

/// Provides JSON utility defaults for the workflows layer.
class WorkflowsJsonUtilitiesOptions {
  static final JsonSerializerOptions defaultOptions = JsonSerializerOptions();
}
