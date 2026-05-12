import 'package:extensions/ai.dart';

import 'ai_context_provider.dart';
import 'chat_history_provider.dart';

/// Represents additional context information that can be dynamically provided
/// to AI models during agent invocations.
///
/// Remarks: [AIContext] serves as a container for contextual information that
/// [AIContextProvider] instances can supply to enhance AI model interactions.
/// This context is merged with the agent's base configuration before being
/// passed to the underlying AI model. The context system enables dynamic,
/// runtime-specific enhancements to agent capabilities including: Adding
/// relevant background information from knowledge bases Injecting
/// task-specific instructions or guidelines Providing specialized tools or
/// functions for the current interaction Including contextual messages that
/// inform the AI about the current situation Context information is transient
/// by default and applies only to the current invocation, however messages
/// added through the [Messages] property will be permanently incorporated
/// into the conversation history.
class AIContext {
  AIContext();

  /// Gets or sets additional instructions to provide to the AI model for the
  /// current invocation.
  ///
  /// Remarks: These instructions are transient and apply only to the current AI
  /// model invocation. They are combined with any existing agent instructions,
  /// system prompts, and conversation history to provide comprehensive context
  /// to the AI model. Instructions can be used to: Provide context-specific
  /// behavioral guidance Add domain-specific knowledge or constraints Modify
  /// the agent's persona or response style for the current interaction Include
  /// situational awareness information
  String? instructions;

  /// Gets or sets the sequence of messages to use for the current invocation.
  ///
  /// Remarks: Unlike [Instructions] and [Tools], messages added through this
  /// property may become permanent additions to the conversation history. If
  /// chat history is managed by the underlying AI service, these messages will
  /// become part of chat history. If chat history is managed using a
  /// [ChatHistoryProvider], these messages will be passed to the
  /// [CancellationToken)] method, and the provider can choose which of these
  /// messages to permanently add to the conversation history. This property is
  /// useful for: Injecting relevant historical context e.g. memories Injecting
  /// relevant background information e.g. via Retrieval Augmented Generation
  /// Adding system messages that provide ongoing context
  Iterable<ChatMessage>? messages;

  /// Gets or sets a sequence of tools or functions to make available to the AI
  /// model for the current invocation.
  ///
  /// Remarks: These tools are transient and apply only to the current AI model
  /// invocation. Any existing tools are provided as input to the
  /// [AIContextProvider] instances, so context providers can choose to modify
  /// or replace the existing tools as needed based on the current context. The
  /// resulting set of tools is then passed to the underlying AI model, which
  /// may choose to utilize them when generating responses. Context-specific
  /// tools enable: Providing specialized functions based on user intent or
  /// conversation context Adding domain-specific capabilities for particular
  /// types of queries Enabling access to external services or data sources
  /// relevant to the current task Offering interactive capabilities tailored to
  /// the current conversation state
  Iterable<AITool>? tools;
}
