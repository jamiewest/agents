import 'package:extensions/ai.dart';

/// Replaces expired volatile-tool results in [messages] with a stale marker.
///
/// Tools such as `get_current_time` return values that are only correct at
/// the moment of the call. When a durable transcript is replayed on a later
/// turn, small models tend to copy the old result instead of calling the
/// tool again. Redacting the payload removes the temptation: the model sees
/// an explicit expired marker directing it back to the tool.
///
/// A result is redacted when its recorded tool name is in [staleToolNames],
/// or when its call id pairs with an earlier [FunctionCallContent] whose
/// name is. The replacement payload is deterministic, so the rendered
/// prompt stays byte-stable across turns and does not disturb prompt-prefix
/// caching. Messages are modified in place; callers pass freshly decoded
/// history, never a shared canonical copy.
void redactStaleToolResults(
  Iterable<ChatMessage> messages,
  Set<String> staleToolNames,
) {
  if (staleToolNames.isEmpty) return;

  final volatileCallNames = <String, String>{};
  for (final message in messages) {
    final contents = message.contents;
    for (var i = 0; i < contents.length; i++) {
      final content = contents[i];
      if (content is FunctionCallContent) {
        if (staleToolNames.contains(content.name)) {
          volatileCallNames[content.callId] = content.name;
        }
        continue;
      }
      if (content is! FunctionResultContent) continue;
      final name = content.name ?? volatileCallNames[content.callId];
      if (name == null || !staleToolNames.contains(name)) continue;
      contents[i] = FunctionResultContent(
        callId: content.callId,
        name: content.name,
        result: {
          'stale': true,
          'note':
              'This result has expired. Call $name again for a current '
              'value.',
        },
      );
    }
  }
}
