// ignore_for_file: non_constant_identifier_names
import 'package:extensions/ai.dart';

import 'agent_session.dart';
import 'in_memory_chat_history_provider.dart';

// ChatReducer is re-exported from package:extensions/ai.dart

/// Configuration options for [InMemoryChatHistoryProvider].
class InMemoryChatHistoryProviderOptions {
  InMemoryChatHistoryProviderOptions();

  /// Optional delegate that initializes the provider state on first
  /// invocation. If `null`, a default empty-state initializer is used.
  InMemoryChatHistoryProviderState Function(AgentSession?)? stateInitializer;

  /// Optional [ChatReducer] that processes or reduces chat messages.
  ChatReducer? chatReducer;

  /// When the message reducer should be invoked. Defaults to
  /// [ChatReducerTriggerEvent.beforeMessagesRetrieval].
  ChatReducerTriggerEvent reducerTriggerEvent =
      ChatReducerTriggerEvent.beforeMessagesRetrieval;

  /// Optional key for storing state in the session state bag.
  String? stateKey;

  /// Optional JSON serializer options (reserved for future use; Dart uses
  /// `dart:convert` by default).
  Object? JsonSerializerOptions;

  /// Optional filter applied to request messages before storage.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
      storageInputRequestMessageFilter;

  /// Optional filter applied to response messages before storage.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
      storageInputResponseMessageFilter;

  /// Optional filter applied to messages produced by this provider.
  Iterable<ChatMessage> Function(Iterable<ChatMessage>)?
      provideOutputMessageFilter;
}

/// Defines when a [ChatReducer] is triggered in [InMemoryChatHistoryProvider].
enum ChatReducerTriggerEvent {
  /// Trigger after a new message is added.
  afterMessageAdded,

  /// Trigger before messages are retrieved from the provider.
  beforeMessagesRetrieval,
}
