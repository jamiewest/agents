import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart' as ai;
import 'package:flutter_test/flutter_test.dart';

/// Guards the persisted transcript record shape shared between
/// [FlutterChatHistoryProvider] (the writer, during agent invocation) and
/// [ChatTranscriptStore] (the display reader).
///
/// Both sides compile against [ChatMessageRecords], so a *rename* of a
/// constant cannot drift silently — but a change to a constant's *string
/// value* would orphan every record already on disk. These tests pin the
/// wire literals and prove a written record round-trips.
void main() {
  test(
    'record field literals never change (existing data depends on them)',
    () {
      expect(ChatMessageRecords.collection, 'chat_messages');
      expect(ChatMessageRecords.conversationIdField, 'conversationId');
      expect(ChatMessageRecords.sessionIdField, 'sessionId');
      expect(ChatMessageRecords.seqField, 'seq');
      expect(ChatMessageRecords.senderAgentIdField, 'senderAgentId');
      expect(ChatMessageRecords.createdAtField, 'createdAt');
      expect(ChatMessageRecords.messageField, 'message');
    },
  );

  test(
    'a record in the provider write shape loads as a transcript entry',
    () async {
      final records = InMemoryRecordStore();
      // Mirror FlutterChatHistoryProvider.storeChatHistory's record literal.
      final message = ai.ChatMessage.fromText(
        ai.ChatRole.assistant,
        'hello from the agent',
      );
      await records.putAll(ChatMessageRecords.collection, {
        'r1': {
          ChatMessageRecords.conversationIdField: 'conv-1',
          ChatMessageRecords.sessionIdField: 'session-1',
          ChatMessageRecords.seqField: 0,
          ChatMessageRecords.senderAgentIdField: 'agent-9',
          ChatMessageRecords.createdAtField: DateTime.utc(
            2026,
            7,
            29,
          ).toIso8601String(),
          ChatMessageRecords.messageField: ChatMessageCodec.encode(message),
        },
      });

      final entries = await ChatTranscriptStore(records).load('conv-1');

      final entry = entries.single;
      expect(entry.seq, 0);
      expect(entry.sessionId, 'session-1');
      expect(entry.senderAgentId, 'agent-9');
      expect(entry.message.role, ai.ChatRole.assistant);
      expect(entry.message.text, 'hello from the agent');
    },
  );

  test('replace() writes records the transcript reader round-trips', () async {
    final records = InMemoryRecordStore();
    final store = ChatTranscriptStore(records);

    await store.replace(
      conversationId: 'conv-1',
      sessionId: 'session-2',
      senderAgentId: 'agent-9',
      messages: [
        ai.ChatMessage.fromText(ai.ChatRole.user, 'hi'),
        ai.ChatMessage.fromText(ai.ChatRole.assistant, 'hello'),
      ],
    );

    final entries = await store.load('conv-1');
    expect(entries, hasLength(2));
    expect(entries[0].seq, 0);
    expect(entries[0].message.role, ai.ChatRole.user);
    // User messages carry no sender agent, matching the provider's schema.
    expect(entries[0].senderAgentId, isNull);
    expect(entries[1].seq, 1);
    expect(entries[1].senderAgentId, 'agent-9');
  });
}
