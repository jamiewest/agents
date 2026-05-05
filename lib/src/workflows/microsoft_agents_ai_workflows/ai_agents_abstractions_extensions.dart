import 'package:extensions/ai.dart';
extension AIAgentsAbstractionsExtensions on ChatMessage {ChatMessage chatAssistantToUserIfNotFromNamed(
  String agentName,
  {bool? changed, bool? inplace, },
) {
changed = false;
if (message.role == ChatRole.assistant &&
            ! == message.authorName, agentName &&
            message.contents.every((c) => c is TextContent or DataContent or UriContent or UsageContent)) {
  if (!inplace) {
    message = message.clone();
  }

  message.role = ChatRole.user;
  changed = true;
}
return message;
 }
/// Iterates through `messages` looking for [Assistant] messages and swapping
/// any that have a different [AuthorName] from `targetAgentName` to [User].
List<ChatMessage>? changeAssistantToUserForOtherParticipants(String targetAgentName) {
var roleChanged = null;
for (final m in messages) {
  m.chatAssistantToUserIfNotFromNamed(targetAgentName, changed);
  if (changed) {
    (roleChanged ??= []).add(m);
  }
}
return roleChanged;
 }
/// Undoes changes made by [String)] when passed the list of changes made by
/// that method.
void resetUserToAssistantForChangedRoles() {
if (roleChanged != null) {
  for (final m in roleChanged) {
    m.role = ChatRole.assistant;
  }
}
 }
 }
