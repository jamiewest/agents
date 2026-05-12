import 'package:extensions/ai.dart';

/// Represents a single streaming response chunk from an [AIAgent].
class AgentResponseUpdate {
  /// Creates an [AgentResponseUpdate] from a [ChatResponseUpdate], or with
  /// an explicit [role] and [contents].
  AgentResponseUpdate({
    ChatResponseUpdate? chatResponseUpdate,
    ChatRole? role,
    String? content,
    List<AIContent>? contents,
  }) {
    if (chatResponseUpdate != null) {
      this.role = chatResponseUpdate.role;
      _contents = List<AIContent>.of(chatResponseUpdate.contents);
      rawRepresentation = chatResponseUpdate;
    } else {
      this.role = role;
      if (content != null) {
        _contents = [TextContent(content)];
      } else {
        _contents = contents;
      }
    }
  }

  List<AIContent>? _contents;

  /// The name of the author of this update.
  String? authorName;

  /// The role of the author of this update.
  late ChatRole? role;

  /// The content items for this update.
  List<AIContent> get contents => _contents ??= [];
  set contents(List<AIContent> value) => _contents = value;

  /// The raw underlying implementation Object, if any.
  Object? rawRepresentation;

  /// Additional provider-specific metadata.
  AdditionalPropertiesDictionary? additionalProperties;

  /// The identifier of the agent that produced this update.
  String? agentId;

  /// The identifier of the response this update belongs to.
  String? responseId;

  /// The identifier of the message this update belongs to.
  String? messageId;

  /// Timestamp for this update.
  DateTime? createdAt;

  /// Continuation token for resuming a background stream.
  ResponseContinuationToken? continuationToken;

  /// The reason this response finished, if applicable.
  ChatFinishReason? finishReason;

  /// The concatenated text content of this update.
  String get text => _contents?.map((c) => c is TextContent ? c.text : '').join() ?? '';

  @override
  String toString() => text;
}
