import 'package:agents/src/abstractions/agent_response.dart';
import 'package:agents/src/abstractions/agent_response_update.dart';
import 'package:extensions/ai.dart';
import 'package:test/test.dart';

void main() {
  group('AgentResponse', () {
    test('constructorWithNullEmptyArgsIsValid', () {
      final response = AgentResponse();

      expect(response.messages, isEmpty);
      expect(response.text, '');
      expect(response.finishReason, isNull);
    });

    test('constructorWithMessagesRoundtrips', () {
      final msgs = [
        ChatMessage.fromText(ChatRole.assistant, 'hello'),
        ChatMessage.fromText(ChatRole.assistant, ' world'),
      ];

      final response = AgentResponse(messages: msgs);

      expect(response.messages, hasLength(2));
      expect(response.messages[0].text, 'hello');
      expect(response.messages[1].text, ' world');
    });

    test('constructorWithChatResponseRoundtrips', () {
      final chatMessages = [
        ChatMessage.fromText(ChatRole.assistant, 'hi'),
      ];
      final chatResponse = ChatResponse(
        messages: chatMessages,
        finishReason: ChatFinishReason.stop,
      );

      final response = AgentResponse(response: chatResponse);

      expect(response.messages, hasLength(1));
      expect(response.messages.first.text, 'hi');
      expect(response.finishReason, ChatFinishReason.stop);
      expect(response.rawRepresentation, same(chatResponse));
    });

    test('textGetConcatenatesAllTextContent', () {
      final response = AgentResponse(
        messages: [
          ChatMessage.fromText(ChatRole.assistant, 'foo'),
          ChatMessage.fromText(ChatRole.assistant, 'bar'),
        ],
      );

      expect(response.text, 'foobar');
    });

    test('textGetReturnsEmptyStringWithNoMessages', () {
      final response = AgentResponse();

      expect(response.text, '');
    });

    test('toStringOutputsText', () {
      final response = AgentResponse(
        message: ChatMessage.fromText(ChatRole.assistant, 'hello'),
      );

      expect(response.toString(), response.text);
    });

    test('toAgentResponseUpdatesProducesUpdates', () {
      final response = AgentResponse(
        messages: [
          ChatMessage.fromText(ChatRole.assistant, 'a'),
          ChatMessage.fromText(ChatRole.assistant, 'b'),
        ],
      );

      final updates = response.toAgentResponseUpdates();

      expect(updates, hasLength(2));
      expect(updates[0].text, 'a');
      expect(updates[1].text, 'b');
    });

    test('toAgentResponseUpdatesWithNoMessagesProducesEmptyArray', () {
      final response = AgentResponse();

      final updates = response.toAgentResponseUpdates();

      expect(updates, isEmpty);
    });

    test('toAgentResponseUpdatesWithUsageOnlyProducesSingleUpdate', () {
      final response = AgentResponse()
        ..usage = UsageDetails(inputTokenCount: 10, outputTokenCount: 5);

      final updates = response.toAgentResponseUpdates();

      expect(updates, hasLength(1));
      expect(
        updates.first.contents.whereType<UsageContent>(),
        isNotEmpty,
      );
    });
  });
}
