import 'package:extensions/ai.dart';

import 'ai_context_provider.dart';
import 'chat_history_provider.dart';

/// Additional context that [AIContextProvider] instances supply to enhance
/// AI model interactions during agent invocations.
///
/// This context is merged with the agent's base configuration before being
/// passed to the underlying AI model. Context information is transient by
/// default and applies only to the current invocation; however, messages
/// added through [messages] may be permanently incorporated into conversation
/// history.
class AIContext {
  AIContext();

  /// Additional instructions to provide to the AI model for this invocation.
  ///
  /// These instructions are transient and apply only to the current invocation.
  /// They are combined with any existing agent instructions, system prompts,
  /// and conversation history before being passed to the AI model.
  String? instructions;

  /// Messages to include in the current invocation.
  ///
  /// Unlike [instructions] and [tools], messages added here may become
  /// permanent additions to the conversation history. If chat history is
  /// managed by the underlying AI service, these messages will become part of
  /// that history. If a [ChatHistoryProvider] is used, it decides which
  /// messages to retain permanently.
  Iterable<ChatMessage>? messages;

  /// Tools or functions to make available to the AI model for this invocation.
  ///
  /// These tools are transient and apply only to the current invocation.
  /// [AIContextProvider] instances receive the existing tools as input and may
  /// modify or replace them. The resulting set is passed to the AI model, which
  /// may invoke them when generating responses.
  Iterable<AITool>? tools;
}
