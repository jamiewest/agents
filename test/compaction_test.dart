// ignore_for_file: non_constant_identifier_names

import 'package:agents/src/abstractions/agent_session.dart';
import 'package:agents/src/abstractions/agent_session_state_bag.dart';
import 'package:agents/src/abstractions/ai_agent.dart';
import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:agents/src/abstractions/agent_run_options.dart';
import 'package:agents/src/abstractions/ai_context.dart';
import 'package:agents/src/abstractions/ai_context_provider.dart';
import 'package:agents/src/ai/compaction/chat_reducer_compaction_strategy.dart';
import 'package:agents/src/ai/compaction/chat_strategy_extensions.dart';
import 'package:agents/src/ai/compaction/compaction_group_kind.dart';
import 'package:agents/src/ai/compaction/compaction_message_group.dart';
import 'package:agents/src/ai/compaction/compaction_message_index.dart';
import 'package:agents/src/ai/compaction/compaction_provider.dart';
import 'package:agents/src/ai/compaction/compaction_triggers.dart';
import 'package:agents/src/ai/compaction/sliding_window_compaction_strategy.dart';
import 'package:agents/src/ai/compaction/summarization_compaction_strategy.dart';
import 'package:agents/src/ai/compaction/tool_result_compaction_strategy.dart';
import 'package:agents/src/ai/compaction/truncation_compaction_strategy.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('CompactionMessageIndex', () {
    test('groups messages into upstream-shaped groups and metrics', () {
      final messages = _messagesWithToolCall();

      final index = CompactionMessageIndex.create(messages);

      expect(index.groups.map((g) => g.kind), [
        CompactionGroupKind.system,
        CompactionGroupKind.user,
        CompactionGroupKind.toolCall,
        CompactionGroupKind.user,
        CompactionGroupKind.assistantText,
      ]);
      expect(index.includedTurnCount, 2);
      expect(index.includedMessageCount, messages.length);
      expect(index.rawMessageCount, messages.length);
      expect(index.includedNonSystemGroupCount, 4);
    });

    test('recognizes summary messages and updates incrementally', () {
      final first = [
        ChatMessage.fromText(ChatRole.user, 'hello'),
        ChatMessage.fromText(ChatRole.assistant, 'hi'),
      ];
      final index = CompactionMessageIndex.create(first);

      final summary = ChatMessage.fromText(ChatRole.assistant, 'summary')
        ..additionalProperties = {
          CompactionMessageGroup.summaryPropertyKey: true,
        };
      index.update([
        ...first,
        summary,
        ChatMessage.fromText(ChatRole.user, 'next'),
      ]);

      expect(index.groups.map((g) => g.kind), [
        CompactionGroupKind.user,
        CompactionGroupKind.assistantText,
        CompactionGroupKind.summary,
        CompactionGroupKind.user,
      ]);
    });

    test('uses tokenizer when provided', () {
      final index = CompactionMessageIndex.create([
        ChatMessage.fromText(ChatRole.user, 'one two three'),
      ], tokenizer: _WhitespaceTokenizer());

      expect(index.includedTokenCount, 3);
    });
  });

  group('CompactionTriggers', () {
    test('evaluate common index metrics', () {
      final index = CompactionMessageIndex.create(_messagesWithToolCall());

      expect(CompactionTriggers.messagesExceed(3)(index), isTrue);
      expect(CompactionTriggers.turnsExceed(1)(index), isTrue);
      expect(CompactionTriggers.groupsExceed(4)(index), isTrue);
      expect(CompactionTriggers.hasToolCalls()(index), isTrue);
      expect(
        CompactionTriggers.all([
          CompactionTriggers.messagesExceed(3),
          CompactionTriggers.hasToolCalls(),
        ])(index),
        isTrue,
      );
    });
  });

  group('CompactionStrategy', () {
    test('truncation excludes oldest non-system groups', () async {
      final index = CompactionMessageIndex.create(_plainConversation());
      final strategy = TruncationCompactionStrategy(
        CompactionTriggers.groupsExceed(3),
        minimumPreservedGroups: 2,
      );

      final compacted = await strategy.compact(index);

      expect(compacted, isTrue);
      expect(index.groups.where((g) => g.isExcluded).map((g) => g.kind), [
        CompactionGroupKind.user,
        CompactionGroupKind.assistantText,
      ]);
      expect(index.getIncludedMessages().map((m) => m.text), [
        'system',
        'question 2',
        'answer 2',
      ]);
    });

    test('sliding window excludes oldest turns', () async {
      final index = CompactionMessageIndex.create(_plainConversation());
      final strategy = SlidingWindowCompactionStrategy(
        CompactionTriggers.turnsExceed(1),
        minimumPreservedTurns: 1,
      );

      final compacted = await strategy.compact(index);

      expect(compacted, isTrue);
      expect(index.getIncludedMessages().map((m) => m.text), [
        'system',
        'question 2',
        'answer 2',
      ]);
    });

    test(
      'tool result compaction inserts summary and excludes tool group',
      () async {
        final index = CompactionMessageIndex.create(_messagesWithToolCall());
        final strategy = ToolResultCompactionStrategy(
          CompactionTriggers.hasToolCalls(),
        );

        final compacted = await strategy.compact(index);

        expect(compacted, isTrue);
        final summaryGroup = index.groups.singleWhere(
          (g) => g.kind == CompactionGroupKind.summary,
        );
        expect(summaryGroup.messages.single.text, contains('[Tool Calls]'));
        expect(summaryGroup.messages.single.text, contains('get_weather:'));
        expect(summaryGroup.messages.single.text, contains('72F'));
        expect(
          summaryGroup
              .messages
              .single
              .additionalProperties?[CompactionMessageGroup.summaryPropertyKey],
          isTrue,
        );
      },
    );

    test('pipeline runs strategies sequentially', () async {
      final index = CompactionMessageIndex.create(_messagesWithToolCall());
      final strategy = ToolResultCompactionStrategy(
        CompactionTriggers.hasToolCalls(),
      );

      final compacted = await strategy.asChatReducer().reduce(
        index.getIncludedMessages().toList(),
      );

      expect(compacted.map((m) => m.text).join('\n'), contains('[Tool Calls]'));
    });

    test('chat reducer strategy rebuilds from reduced messages', () async {
      final index = CompactionMessageIndex.create(_plainConversation());
      final strategy = ChatReducerCompactionStrategy(
        _TakeLastReducer(2),
        CompactionTriggers.always,
      );

      final compacted = await strategy.compact(index);

      expect(compacted, isTrue);
      expect(index.getIncludedMessages().map((m) => m.text), [
        'question 2',
        'answer 2',
      ]);
    });

    test('summarization replaces older groups with summary message', () async {
      final index = CompactionMessageIndex.create(_plainConversation());
      final chatClient = _SummaryChatClient('short summary');
      final strategy = SummarizationCompactionStrategy(
        chatClient,
        CompactionTriggers.groupsExceed(2),
        minimumPreservedGroups: 1,
      );

      final compacted = await strategy.compact(index);

      expect(compacted, isTrue);
      expect(
        chatClient.capturedMessages.single.first.text,
        contains('Summarize'),
      );
      expect(index.getIncludedMessages().map((m) => m.text), [
        'system',
        '[Summary]\nshort summary',
        'answer 2',
      ]);
    });
  });

  group('CompactionProvider', () {
    test('compact helper returns included messages', () async {
      final compacted = await CompactionProvider.compact(
        TruncationCompactionStrategy(
          CompactionTriggers.groupsExceed(3),
          minimumPreservedGroups: 2,
        ),
        _plainConversation(),
      );

      expect(compacted.map((m) => m.text), [
        'system',
        'question 2',
        'answer 2',
      ]);
    });

    test(
      'invoking persists message groups and returns compacted context',
      () async {
        final provider = CompactionProvider(
          TruncationCompactionStrategy(
            CompactionTriggers.groupsExceed(3),
            minimumPreservedGroups: 2,
          ),
        );
        final session = _TestSession();
        final agent = _TestAgent();

        final context = await provider.invokingCore(
          InvokingContext(
            agent,
            session,
            AIContext()..messages = _plainConversation(),
          ),
        );

        expect(context.messages!.map((m) => m.text), [
          'system',
          'question 2',
          'answer 2',
        ]);
        expect(session.stateBag.count, 1);
      },
    );
  });
}

List<ChatMessage> _plainConversation() => [
  ChatMessage.fromText(ChatRole.system, 'system'),
  ChatMessage.fromText(ChatRole.user, 'question 1'),
  ChatMessage.fromText(ChatRole.assistant, 'answer 1'),
  ChatMessage.fromText(ChatRole.user, 'question 2'),
  ChatMessage.fromText(ChatRole.assistant, 'answer 2'),
];

List<ChatMessage> _messagesWithToolCall() => [
  ChatMessage.fromText(ChatRole.system, 'system'),
  ChatMessage.fromText(ChatRole.user, 'weather?'),
  ChatMessage(
    role: ChatRole.assistant,
    contents: [
      FunctionCallContent(
        callId: 'call-1',
        name: 'get_weather',
        arguments: {'city': 'Seattle'},
      ),
    ],
  ),
  ChatMessage(
    role: ChatRole.tool,
    contents: [FunctionResultContent(callId: 'call-1', result: '72F')],
  ),
  ChatMessage.fromText(ChatRole.user, 'thanks'),
  ChatMessage.fromText(ChatRole.assistant, 'done'),
];

class _WhitespaceTokenizer implements Tokenizer {
  @override
  int countTokens(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
  }
}

class _TakeLastReducer extends ChatReducer {
  _TakeLastReducer(this.count);

  final int count;

  @override
  Future<List<ChatMessage>> reduce(
    List<ChatMessage> messages, {
    CancellationToken? cancellationToken,
  }) async => messages.skip(messages.length - count).toList();
}

class _SummaryChatClient extends ChatClient {
  _SummaryChatClient(this.summary);

  final String summary;
  final List<List<ChatMessage>> capturedMessages = [];

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    capturedMessages.add(messages.toList());
    return ChatResponse.fromMessage(
      ChatMessage.fromText(ChatRole.assistant, summary),
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}

  @override
  void dispose() {}
}

class _TestSession extends AgentSession {
  _TestSession() : super(AgentSessionStateBag(null));
}

class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => _TestSession();

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? JsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) async => {};

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async =>
      AgentResponse(messages: [ChatMessage.fromText(ChatRole.assistant, 'ok')]);

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {}
}
