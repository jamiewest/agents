import 'dart:typed_data';

import 'package:agents/src/ai/compaction/compaction_group_kind.dart';
import 'package:agents/src/ai/compaction/compaction_message_group.dart';
import 'package:agents/src/ai/compaction/compaction_message_index.dart';
import 'package:extensions/ai.dart';
import 'package:test/test.dart';

void main() {
  // ── Group creation ─────────────────────────────────────────────────────────

  group('CompactionMessageIndex.create — group kinds', () {
    test('createEmptyListReturnsEmptyGroups', () {
      final index = CompactionMessageIndex.create([]);
      expect(index.groups, isEmpty);
    });

    test('createSystemMessageCreatesSystemGroup', () {
      final index = CompactionMessageIndex.create([_system('sys')]);
      expect(index.groups.single.kind, CompactionGroupKind.system);
    });

    test('createUserMessageCreatesUserGroup', () {
      final index = CompactionMessageIndex.create([_user('hi')]);
      expect(index.groups.single.kind, CompactionGroupKind.user);
    });

    test('createAssistantTextMessageCreatesAssistantTextGroup', () {
      final index = CompactionMessageIndex.create([_assistant('reply')]);
      expect(index.groups.single.kind, CompactionGroupKind.assistantText);
    });

    test('createToolCallWithResultsCreatesAtomicGroup', () {
      final callId = 'call-1';
      final messages = [
        _assistantWithCall('get_weather', callId),
        _toolResult(callId, 'sunny'),
      ];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups.single.kind, CompactionGroupKind.toolCall);
      expect(index.groups.single.messages, hasLength(2));
    });

    test('createMixedConversationGroupsCorrectly', () {
      final messages = [
        _system('instructions'),
        _user('hello'),
        _assistantWithCall('fn', 'c1'),
        _toolResult('c1', 'result'),
        _assistant('done'),
      ];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups.map((g) => g.kind), [
        CompactionGroupKind.system,
        CompactionGroupKind.user,
        CompactionGroupKind.toolCall,
        CompactionGroupKind.assistantText,
      ]);
    });

    test('createMultipleToolResultsGroupsAllWithAssistant', () {
      final messages = [
        _user('go'),
        ChatMessage(
          role: ChatRole.assistant,
          contents: [
            FunctionCallContent(callId: 'c1', name: 'fnA'),
            FunctionCallContent(callId: 'c2', name: 'fnB'),
          ],
        ),
        _toolResult('c1', 'resultA'),
        _toolResult('c2', 'resultB'),
      ];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups, hasLength(2));
      final toolGroup = index.groups.last;
      expect(toolGroup.kind, CompactionGroupKind.toolCall);
      expect(toolGroup.messages, hasLength(3));
    });

    test('createSummaryMessageCreatesSummaryGroup', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        contents: [TextContent('summary here')],
        additionalProperties: {CompactionMessageGroup.summaryPropertyKey: true},
      );
      final index = CompactionMessageIndex.create([msg]);
      expect(index.groups.single.kind, CompactionGroupKind.summary);
    });

    test('createWithStandaloneToolMessageGroupsAsAssistantText', () {
      // Orphaned tool result without preceding assistant+call → assistantText
      final index = CompactionMessageIndex.create([
        _toolResult('orphan', 'value'),
      ]);
      expect(index.groups.single.kind, CompactionGroupKind.assistantText);
    });

    test('createWithSummaryPropertyFalseIsNotSummary', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        contents: [TextContent('text')],
        additionalProperties: {CompactionMessageGroup.summaryPropertyKey: false},
      );
      final index = CompactionMessageIndex.create([msg]);
      expect(index.groups.single.kind, CompactionGroupKind.assistantText);
    });

    test('createWithSummaryPropertyNonBoolIsNotSummary', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        contents: [TextContent('text')],
        additionalProperties: {
          CompactionMessageGroup.summaryPropertyKey: 'true',
        },
      );
      final index = CompactionMessageIndex.create([msg]);
      expect(index.groups.single.kind, CompactionGroupKind.assistantText);
    });

    test('createWithNoAdditionalPropertiesIsNotSummary', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        contents: [TextContent('text')],
      );
      final index = CompactionMessageIndex.create([msg]);
      expect(index.groups.single.kind, CompactionGroupKind.assistantText);
    });
  });

  // ── Turn index assignment ──────────────────────────────────────────────────

  group('CompactionMessageIndex.create — turn indices', () {
    test('createAssignsTurnIndicesSingleTurn', () {
      final index = CompactionMessageIndex.create([
        _system('sys'),
        _user('hi'),
        _assistant('reply'),
      ]);
      expect(index.groups[0].turnIndex, isNull); // system
      expect(index.groups[1].turnIndex, 1); // user turn 1
      expect(index.groups[2].turnIndex, 1); // assistant still turn 1
    });

    test('createAssignsTurnIndicesMultiTurn', () {
      final index = CompactionMessageIndex.create([
        _user('q1'),
        _assistant('a1'),
        _user('q2'),
        _assistant('a2'),
        _user('q3'),
      ]);
      expect(index.groups[0].turnIndex, 1);
      expect(index.groups[1].turnIndex, 1);
      expect(index.groups[2].turnIndex, 2);
      expect(index.groups[3].turnIndex, 2);
      expect(index.groups[4].turnIndex, 3);
    });

    test('createTurnSpansToolCallGroups', () {
      final messages = [
        _user('go'),
        _assistantWithCall('fn', 'c1'),
        _toolResult('c1', 'r'),
        _assistant('done'),
      ];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups[0].turnIndex, 1); // user
      expect(index.groups[1].turnIndex, 1); // toolCall
      expect(index.groups[2].turnIndex, 1); // assistantText
    });

    test('getTurnGroupsReturnsGroupsForSpecificTurn', () {
      final index = CompactionMessageIndex.create([
        _user('q1'),
        _assistant('a1'),
        _user('q2'),
        _assistant('a2'),
      ]);
      final turn1 =
          index.groups.where((g) => g.turnIndex == 1).toList();
      expect(turn1, hasLength(2));
    });

    test('totalTurnCountZeroWhenNoUserMessages', () {
      final index = CompactionMessageIndex.create([_system('sys')]);
      final turnIndices = index.groups
          .where((g) => g.turnIndex != null)
          .map((g) => g.turnIndex)
          .toSet();
      expect(turnIndices, isEmpty);
    });
  });

  // ── Exclusion and included metrics ────────────────────────────────────────

  group('CompactionMessageIndex — exclusion', () {
    test('getIncludedMessagesExcludesMarkedGroups', () {
      final index = CompactionMessageIndex.create([
        _system('sys'),
        _user('hi'),
        _assistant('reply'),
      ]);
      index.groups[1].isExcluded = true; // exclude user

      final included = index.getIncludedMessages().toList();
      expect(included, hasLength(2)); // system + assistant
    });

    test('getAllMessagesIncludesExcludedGroups', () {
      final index = CompactionMessageIndex.create([
        _system('sys'),
        _user('hi'),
      ]);
      index.groups.first.isExcluded = true;

      final all = index.groups.expand((g) => g.messages).toList();
      expect(all, hasLength(2));
    });

    test('includedGroupCountReflectsExclusions', () {
      final index = CompactionMessageIndex.create([
        _system('sys'),
        _user('hi'),
        _assistant('reply'),
      ]);
      index.groups[0].isExcluded = true;

      expect(index.includedGroupCount, 2);
      expect(index.totalGroupCount, 3);
    });

    test('includedTurnCountReflectsExclusions', () {
      final index = CompactionMessageIndex.create([
        _user('q1'),
        _assistant('a1'),
        _user('q2'),
        _assistant('a2'),
      ]);
      // Exclude all of turn 1
      index.groups[0].isExcluded = true;
      index.groups[1].isExcluded = true;

      expect(index.includedTurnCount, 1); // only turn 2 remains
    });

    test('includedTurnCountPartialExclusionStillCountsTurn', () {
      final index = CompactionMessageIndex.create([
        _user('q1'),
        _assistant('a1'),
        _user('q2'),
        _assistant('a2'),
      ]);
      index.groups[1].isExcluded = true; // only assistant in turn 1 excluded

      expect(index.includedTurnCount, 2); // both turns still present
    });
  });

  // ── Aggregate metrics ──────────────────────────────────────────────────────

  group('CompactionMessageIndex — aggregate metrics', () {
    test('totalAggregatesSumAllGroups', () {
      final index = CompactionMessageIndex.create([
        _user('hi'), // 2 bytes
        _assistant('bye'), // 3 bytes
      ]);
      index.groups[0].isExcluded = true;

      // totalByteCount includes excluded groups
      expect(index.totalByteCount, greaterThan(0));
      expect(index.totalMessageCount, 2);
    });

    test('includedAggregatesExcludeMarkedGroups', () {
      final index = CompactionMessageIndex.create([
        _user('hello'), // 5 bytes
        _assistant('world'), // 5 bytes
      ]);
      index.groups[0].isExcluded = true;

      expect(index.includedMessageCount, 1);
      expect(index.includedByteCount,
          CompactionMessageIndex.computeByteCount([_assistant('world')]));
    });
  });

  // ── update() ──────────────────────────────────────────────────────────────

  group('CompactionMessageIndex.update', () {
    test('updateAppendsNewMessagesIncrementally', () {
      final messages = [_user('q1'), _assistant('a1')];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups, hasLength(2));

      messages.addAll([_user('q2'), _assistant('a2')]);
      index.update(messages);

      expect(index.groups, hasLength(4));
    });

    test('updateNoOpWhenNoNewMessages', () {
      final messages = [_user('q1'), _assistant('a1')];
      final index = CompactionMessageIndex.create(messages);

      index.update(messages); // same list

      expect(index.groups, hasLength(2));
    });

    test('updateRebuildsWhenMessagesShrink', () {
      final messages = [_user('q1'), _assistant('a1'), _user('q2')];
      final index = CompactionMessageIndex.create(messages);
      index.groups[0].isExcluded = true;

      final shorter = [_user('q1')];
      index.update(shorter);

      // Rebuild cleared exclusions
      expect(index.groups, hasLength(1));
      expect(index.groups[0].isExcluded, isFalse);
    });

    test('updateWithEmptyListClearsGroups', () {
      final index = CompactionMessageIndex.create([_user('hi')]);
      index.update([]);
      expect(index.groups, isEmpty);
    });

    test('updateRebuildsWhenLastProcessedMessageNotFound', () {
      final messages = [_user('first')];
      final index = CompactionMessageIndex.create(messages);

      // Replace with completely different messages
      final different = [_user('other'), _assistant('reply')];
      index.update(different);

      expect(index.groups, hasLength(2));
      expect(index.groups[0].messages[0].text, 'other');
    });

    test('updatePreservesExistingGroupExclusionState', () {
      final messages = [_user('q1'), _assistant('a1')];
      final index = CompactionMessageIndex.create(messages);
      index.groups[0].isExcluded = true;

      messages.add(_user('q2'));
      index.update(messages);

      expect(index.groups[0].isExcluded, isTrue);
    });
  });

  // ── insertGroup / addGroup ─────────────────────────────────────────────────

  group('CompactionMessageIndex insertGroup and addGroup', () {
    test('insertGroupInsertsAtSpecifiedIndex', () {
      final index = CompactionMessageIndex.create([_user('q1'), _assistant('a1')]);

      index.insertGroup(
        1,
        CompactionGroupKind.summary,
        [_summaryMessage('sum')],
      );

      expect(index.groups, hasLength(3));
      expect(index.groups[1].kind, CompactionGroupKind.summary);
    });

    test('addGroupAppendsToEnd', () {
      final index = CompactionMessageIndex.create([_user('q1')]);

      index.addGroup(CompactionGroupKind.assistantText, [_assistant('a1')]);

      expect(index.groups, hasLength(2));
      expect(index.groups.last.kind, CompactionGroupKind.assistantText);
    });

    test('insertGroupComputesByteAndTokenCounts', () {
      final index = CompactionMessageIndex.create([]);
      final msg = _user('Hello'); // 5 bytes

      index.insertGroup(0, CompactionGroupKind.user, [msg]);

      expect(index.groups.single.byteCount, 5);
      expect(index.groups.single.tokenCount, greaterThan(0));
    });
  });

  // ── Constructor restoring from groups ─────────────────────────────────────

  group('CompactionMessageIndex constructor with groups', () {
    test('constructorWithGroupsRestoresTurnIndex', () {
      final groups = [
        CompactionMessageGroup(
          CompactionGroupKind.user,
          [_user('q1')],
          2,
          1,
          turnIndex: 1,
        ),
        CompactionMessageGroup(
          CompactionGroupKind.assistantText,
          [_assistant('a1')],
          2,
          1,
          turnIndex: 1,
        ),
      ];
      final index = CompactionMessageIndex(groups);

      // Adding a user message via update should increment to turn 2
      final messages = [_user('q1'), _assistant('a1'), _user('q2')];
      index.update(messages);

      expect(index.groups.last.turnIndex, 2);
    });

    test('constructorWithEmptyGroupsHandlesGracefully', () {
      expect(() => CompactionMessageIndex([]), returnsNormally);
    });
  });

  // ── MessageGroup properties ────────────────────────────────────────────────

  group('CompactionMessageGroup', () {
    test('messageGroupStoresPassedCounts', () {
      final group = CompactionMessageGroup(
        CompactionGroupKind.user,
        [_user('hi')],
        42,
        10,
        turnIndex: 1,
      );
      expect(group.byteCount, 42);
      expect(group.tokenCount, 10);
      expect(group.messageCount, 1);
      expect(group.turnIndex, 1);
    });

    test('messageGroupMessagesAreCopied', () {
      final messages = [_user('hi')];
      final group = CompactionMessageGroup(
        CompactionGroupKind.user,
        messages,
        2,
        1,
      );
      messages.add(_user('extra'));
      // Mutating original list should not affect group
      expect(group.messages, hasLength(1));
    });
  });

  // ── computeByteCount ──────────────────────────────────────────────────────

  group('CompactionMessageIndex.computeByteCount', () {
    test('createComputesByteCountUtf8', () {
      expect(
        CompactionMessageIndex.computeByteCount([
          ChatMessage(role: ChatRole.user, contents: [TextContent('Hello')]),
        ]),
        5,
      );
    });

    test('createComputesByteCountMultiByteChars', () {
      // "café" — 'é' is 2 bytes in UTF-8
      expect(
        CompactionMessageIndex.computeByteCount([
          ChatMessage(role: ChatRole.user, contents: [TextContent('café')]),
        ]),
        5,
      );
    });

    test('createComputesByteCountMultipleMessagesInGroup', () {
      final callId = 'c1';
      final byteCount = CompactionMessageIndex.computeByteCount([
        _assistantWithCall('get', callId),
        _toolResult(callId, 'r'),
      ]);
      expect(byteCount, greaterThan(0));
    });

    test('computeByteCountTextContent', () {
      final count = CompactionMessageIndex.computeContentByteCount(
        TextContent('Hello'),
      );
      expect(count, 5);
    });

    test('computeByteCountTextReasoningContent', () {
      final protectedBytes = Uint8List.fromList([1, 2, 3]);
      final count = CompactionMessageIndex.computeContentByteCount(
        TextReasoningContent('think', protectedData: protectedBytes),
      );
      // "think" = 5 bytes + 3 protected bytes = 8
      expect(count, 8);
    });

    test('computeByteCountFunctionCallContentWithArguments', () {
      final count = CompactionMessageIndex.computeContentByteCount(
        FunctionCallContent(
          callId: 'id',
          name: 'fn',
          arguments: {'key': 'val'},
        ),
      );
      // Dart does not include callId: "fn"=2 + "key"=3 + "val"=3 = 8
      expect(count, 8);
    });

    test('computeByteCountFunctionCallContentWithoutArguments', () {
      final count = CompactionMessageIndex.computeContentByteCount(
        FunctionCallContent(callId: 'id', name: 'fn'),
      );
      // Only name: "fn" = 2 bytes
      expect(count, 2);
    });

    test('computeByteCountFunctionResultContent', () {
      // Degree symbol "°" is 2 bytes in UTF-8
      final count = CompactionMessageIndex.computeContentByteCount(
        FunctionResultContent(callId: 'id', result: '°'),
      );
      expect(count, 2);
    });

    test('computeByteCountDataContent', () {
      final data = Uint8List.fromList([10, 20, 30]);
      final count = CompactionMessageIndex.computeContentByteCount(
        DataContent(data, mediaType: 'image/png', name: 'img'),
      );
      // 3 bytes data + "image/png"(9) + "img"(3) = 15
      expect(count, 15);
    });

    test('computeByteCountUriContent', () {
      final count = CompactionMessageIndex.computeContentByteCount(
        UriContent(Uri.parse('https://example.com/img'), mediaType: 'image/png'),
      );
      expect(count, greaterThan(0));
    });

    test('computeByteCountErrorContent', () {
      final count = CompactionMessageIndex.computeContentByteCount(
        ErrorContent('oops', errorCode: 'E1'),
      );
      // "oops"(4) + "E1"(2) = 6
      expect(count, 6);
    });

    test('computeByteCountHostedFileContent', () {
      final count = CompactionMessageIndex.computeContentByteCount(
        HostedFileContent(fileId: 'fid', mediaType: 'text/plain', name: 'f'),
      );
      // "fid"(3) + "text/plain"(10) + "f"(1) = 14
      expect(count, 14);
    });

    test('computeByteCountEmptyContentsReturnsZero', () {
      expect(CompactionMessageIndex.computeByteCount([]), 0);
    });

    test('computeByteCountMixedContentInSingleMessage', () {
      final msg = ChatMessage(
        role: ChatRole.user,
        contents: [
          TextContent('hi'), // 2
          TextContent('bye'), // 3
        ],
      );
      expect(CompactionMessageIndex.computeByteCount([msg]), 5);
    });
  });

  // ── computeTokenCount ─────────────────────────────────────────────────────

  group('CompactionMessageIndex.computeTokenCount', () {
    test('computeTokenCountReturnsTokenCount', () {
      final tokenizer = _CharCountTokenizer();
      final count = CompactionMessageIndex.computeTokenCount(
        [ChatMessage(role: ChatRole.user, contents: [TextContent('hello')])],
        tokenizer,
      );
      expect(count, 5); // 1 token per char
    });

    test('computeTokenCountEmptyContentsReturnsZero', () {
      final tokenizer = _CharCountTokenizer();
      expect(CompactionMessageIndex.computeTokenCount([], tokenizer), 0);
    });

    test('createWithTokenizerUsesTokenizerForCounts', () {
      final tokenizer = _CharCountTokenizer();
      final index = CompactionMessageIndex.create(
        [_user('hello')],
        tokenizer: tokenizer,
      );
      expect(index.groups.single.tokenCount, 5);
    });

    test('insertGroupWithTokenizerUsesTokenizer', () {
      final tokenizer = _CharCountTokenizer();
      final index = CompactionMessageIndex.create([], tokenizer: tokenizer);

      index.insertGroup(0, CompactionGroupKind.user, [_user('hi')]);

      expect(index.groups.single.tokenCount, 2);
    });

    test('computeTokenCountTextReasoningContentUsesTokenizer', () {
      final tokenizer = _CharCountTokenizer();
      final protectedData = Uint8List.fromList([1, 2, 3]);
      final count = CompactionMessageIndex.computeTokenCount(
        [
          ChatMessage(
            role: ChatRole.assistant,
            contents: [TextReasoningContent('think', protectedData: protectedData)],
          ),
        ],
        tokenizer,
      );
      // 5 chars tokenized + 3 protected bytes = 8
      expect(count, 8);
    });

    test('computeTokenCountNonTextContentEstimatesFromBytes', () {
      // Without tokenizer, DataContent → ceiling(byteCount/4) heuristic.
      // DataContent byte count = data(4 bytes) only — no mediaType to keep math clean.
      final data = Uint8List.fromList(List.filled(4, 0));
      final index = CompactionMessageIndex.create([
        ChatMessage(
          role: ChatRole.user,
          contents: [DataContent(data, mediaType: '')],
        ),
      ]);
      // 4 bytes / 4 = 1 token
      expect(index.groups.single.tokenCount, 1);
    });
  });

  // ── Reasoning grouping ─────────────────────────────────────────────────────

  group('CompactionMessageIndex — reasoning message grouping', () {
    test('reasoningBeforeToolCallBundlesAtomically', () {
      final messages = [
        _user('q'),
        _reasoning('let me think'),
        _assistantWithCall('fn', 'c1'),
        _toolResult('c1', 'r'),
      ];
      final index = CompactionMessageIndex.create(messages);
      // user + one toolCall group containing reasoning+call+result
      expect(index.groups, hasLength(2));
      expect(index.groups[1].kind, CompactionGroupKind.toolCall);
      expect(index.groups[1].messages, hasLength(3));
    });

    test('multipleReasoningMessagesBeforeToolCall', () {
      final messages = [
        _user('q'),
        _reasoning('step1'),
        _reasoning('step2'),
        _assistantWithCall('fn', 'c1'),
        _toolResult('c1', 'r'),
      ];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups, hasLength(2));
      expect(index.groups[1].kind, CompactionGroupKind.toolCall);
      expect(index.groups[1].messages, hasLength(4));
    });

    test('standaloneReasoningGroupsAsAssistantText', () {
      final messages = [_user('q'), _reasoning('lone thought')];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups[1].kind, CompactionGroupKind.assistantText);
    });

    test('reasoningAtEndOfConversationGroupsAsAssistantText', () {
      final messages = [
        _user('q'),
        _assistant('reply'),
        _reasoning('trailing thought'),
      ];
      final index = CompactionMessageIndex.create(messages);
      expect(index.groups.last.kind, CompactionGroupKind.assistantText);
    });

    test('reasoningFollowedByNonToolCallGroupsAsAssistantText', () {
      final messages = [
        _user('q'),
        _reasoning('think'),
        _assistant('reply'), // plain text, not a tool call
      ];
      final index = CompactionMessageIndex.create(messages);
      // reasoning → assistantText, then assistant → assistantText
      expect(index.groups, hasLength(3));
      expect(index.groups[1].kind, CompactionGroupKind.assistantText);
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ChatMessage _system(String text) =>
    ChatMessage(role: ChatRole.system, contents: [TextContent(text)]);

ChatMessage _user(String text) =>
    ChatMessage(role: ChatRole.user, contents: [TextContent(text)]);

ChatMessage _assistant(String text) =>
    ChatMessage(role: ChatRole.assistant, contents: [TextContent(text)]);

ChatMessage _assistantWithCall(String fn, String callId) => ChatMessage(
      role: ChatRole.assistant,
      contents: [FunctionCallContent(callId: callId, name: fn)],
    );

ChatMessage _toolResult(String callId, String result) => ChatMessage(
      role: ChatRole.tool,
      contents: [FunctionResultContent(callId: callId, result: result)],
    );

ChatMessage _reasoning(String text) => ChatMessage(
      role: ChatRole.assistant,
      contents: [TextReasoningContent(text)],
    );

ChatMessage _summaryMessage(String text) => ChatMessage(
      role: ChatRole.assistant,
      contents: [TextContent(text)],
      additionalProperties: {CompactionMessageGroup.summaryPropertyKey: true},
    );

/// Simple tokenizer that returns the number of characters in the text.
class _CharCountTokenizer implements Tokenizer {
  @override
  int countTokens(String text) => text.length;
}
