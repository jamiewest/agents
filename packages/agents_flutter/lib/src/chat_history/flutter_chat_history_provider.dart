// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../storage/record_store.dart';
import 'chat_message_codec.dart';

/// Field and collection names for persisted chat transcript records.
///
/// Shared between [FlutterChatHistoryProvider] (which writes them during
/// agent invocation) and application UI layers that read the transcript
/// for display.
abstract final class ChatMessageRecords {
  /// The default [RecordStore] collection holding transcript messages.
  static const String collection = 'chat_messages';

  /// The conversation the message belongs to.
  static const String conversationIdField = 'conversationId';

  /// The session (model-context epoch) the message was written under.
  static const String sessionIdField = 'sessionId';

  /// Monotonic per-conversation ordering key.
  static const String seqField = 'seq';

  /// The configured agent that produced the message, when known.
  ///
  /// `null` for messages authored by the human user.
  static const String senderAgentIdField = 'senderAgentId';

  /// ISO-8601 UTC timestamp of when the record was written.
  static const String createdAtField = 'createdAt';

  /// The [ChatMessageCodec]-encoded message payload.
  static const String messageField = 'message';
}

/// A durable [ChatHistoryProvider] backed by a [RecordStore].
///
/// Persists every request/response message of a conversation — including
/// tool calls and results — and provides the full transcript back to the
/// agent on the next invocation, so conversations resume with faithful
/// model context and no replay step. One provider instance serves one
/// conversation; construct it with the conversation's id when building the
/// agent.
class FlutterChatHistoryProvider extends ChatHistoryProvider {
  /// Creates a [FlutterChatHistoryProvider] for one conversation.
  ///
  /// [_sessionIdResolver] supplies the active session id stamped onto new
  /// records, letting the app segment one continuous conversation into
  /// sessions. [_senderAgentId] is stamped onto non-user messages so
  /// multi-agent transcripts stay attributable. [_chatReducer] optionally
  /// reduces the provided history (for compaction parity) without mutating
  /// what is stored.
  FlutterChatHistoryProvider(
    this._store, {
    required this.conversationId,
    required this._sessionIdResolver,
    this._senderAgentId,
    this._chatReducer,
    this._collection = ChatMessageRecords.collection,
  }) : super(storeInputRequestMessageFilter: _excludeInjectedMessages);

  /// Drops request messages the pipeline injects on every invocation —
  /// replayed chat history and AI-context-provider output — so the durable
  /// transcript holds only genuine user and agent turns. Injected context is
  /// regenerated fresh each invocation and would otherwise duplicate in the
  /// transcript on every turn.
  static Iterable<ChatMessage> _excludeInjectedMessages(
    Iterable<ChatMessage> messages,
  ) => messages.where((message) {
    final source = message.getAgentRequestMessageSourceType();
    return source != AgentRequestMessageSourceType.chatHistory &&
        source != AgentRequestMessageSourceType.aiContextProvider;
  });

  /// The conversation this provider reads and writes.
  final String conversationId;

  final RecordStore _store;
  final String Function() _sessionIdResolver;
  final String? _senderAgentId;
  final ChatReducer? _chatReducer;
  final String _collection;

  @override
  Future<Iterable<ChatMessage>> provideChatHistory(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final records = await _store.query(
      _collection,
      query: RecordQuery(
        equals: {ChatMessageRecords.conversationIdField: conversationId},
        orderBy: ChatMessageRecords.seqField,
      ),
    );

    final messages = <ChatMessage>[
      for (final record in records)
        if (record.value[ChatMessageRecords.messageField]
            case final Map<String, Object?> encoded)
          ?ChatMessageCodec.decode(encoded),
    ];

    final reducer = _chatReducer;
    if (reducer == null) {
      return messages;
    }
    return reducer.reduce(messages);
  }

  @override
  Future<void> storeChatHistory(
    InvokedContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final newMessages = [
      ...context.requestMessages,
      ...?context.responseMessages,
    ];
    if (newMessages.isEmpty) {
      return;
    }

    var seq = await _nextSeq();
    final sessionId = _sessionIdResolver();
    final now = DateTime.now().toUtc().toIso8601String();

    for (final message in newMessages) {
      await _store.put(_collection, _newRecordId(), {
        ChatMessageRecords.conversationIdField: conversationId,
        ChatMessageRecords.sessionIdField: sessionId,
        ChatMessageRecords.seqField: seq++,
        if (message.role != ChatRole.user && _senderAgentId != null)
          ChatMessageRecords.senderAgentIdField: _senderAgentId,
        ChatMessageRecords.createdAtField: now,
        ChatMessageRecords.messageField: ChatMessageCodec.encode(message),
      });
    }
  }

  Future<int> _nextSeq() async {
    final latest = await _store.query(
      _collection,
      query: RecordQuery(
        equals: {ChatMessageRecords.conversationIdField: conversationId},
        orderBy: ChatMessageRecords.seqField,
        descending: true,
        limit: 1,
      ),
    );
    if (latest.isEmpty) {
      return 0;
    }
    return (latest.single.value[ChatMessageRecords.seqField]! as int) + 1;
  }

  static String _newRecordId() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}
