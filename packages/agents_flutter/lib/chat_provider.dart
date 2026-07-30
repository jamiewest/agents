/// The chat view-model contract: the bridge between an `AIAgent` and any
/// chat UI.
///
/// This is a separate entry point from `package:agents_flutter/agents_flutter.dart`
/// because [ChatMessage] here is the *UI-facing* message (display text,
/// attachments, origin) and would otherwise collide with
/// `package:extensions/ai.dart`'s wire-level `ChatMessage` in every file
/// that imports both. Import this library from chat UI code; import the
/// main barrel everywhere else.
library;

export 'src/chat_provider/agent_llm_provider.dart';
export 'src/chat_provider/attachments.dart';
export 'src/chat_provider/chat_message.dart';
export 'src/chat_provider/echo_llm_provider.dart';
export 'src/chat_provider/llm_exception.dart';
export 'src/chat_provider/llm_provider.dart';
export 'src/chat_provider/message_origin.dart';
export 'src/chat_provider/token_smoother.dart';
export 'src/chat_provider/tool_approval.dart';
