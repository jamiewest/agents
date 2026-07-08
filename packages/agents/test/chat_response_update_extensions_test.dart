import 'package:extensions/ai.dart';
import 'package:test/test.dart';

/// Contract tests for the `toChatResponse` accumulation behavior that
/// `ChatClientAgent` and related decorators depend on. The implementation
/// lives in `package:extensions/ai.dart` (extensions >= 0.5.0), which
/// replaced the local port that previously lived in this package.
void main() {
  group('ChatResponseUpdatesExtensions.toChatResponse', () {
    test('coalesces contiguous updates into a single message', () {
      // Arrange
      final updates = [
        ChatResponseUpdate(
          role: ChatRole.assistant,
          contents: [TextContent('Hello, ')],
        ),
        ChatResponseUpdate(
          role: ChatRole.assistant,
          contents: [TextContent('world!')],
        ),
      ];

      // Act
      final response = updates.toChatResponse();

      // Assert
      expect(response.messages, hasLength(1));
      expect(response.messages.single.role, ChatRole.assistant);
      expect(response.messages.single.contents, hasLength(2));
    });

    test('starts a new message when the author changes', () {
      // Arrange
      final updates = [
        ChatResponseUpdate(
          role: ChatRole.assistant,
          authorName: 'one',
          contents: [TextContent('first')],
        ),
        ChatResponseUpdate(
          role: ChatRole.assistant,
          authorName: 'other',
          contents: [TextContent('second')],
        ),
      ];

      // Act
      final response = updates.toChatResponse();

      // Assert
      expect(response.messages, hasLength(2));
      expect(response.messages[1].authorName, 'other');
    });

    test('starts a new message when the message ID changes', () {
      // Arrange
      final updates = [
        ChatResponseUpdate(
          role: ChatRole.assistant,
          messageId: 'msg-1',
          contents: [TextContent('first')],
        ),
        ChatResponseUpdate(
          role: ChatRole.assistant,
          messageId: 'msg-2',
          contents: [TextContent('second')],
        ),
      ];

      // Act
      final response = updates.toChatResponse();

      // Assert
      expect(response.messages, hasLength(2));
      expect(response.messages[1].messageId, 'msg-2');
    });

    test('preserves response-level metadata from updates', () {
      // Arrange
      final usage = UsageDetails(
        inputTokenCount: 10,
        outputTokenCount: 5,
        totalTokenCount: 15,
      );
      final updates = [
        ChatResponseUpdate(
          role: ChatRole.assistant,
          responseId: 'resp-1',
          messageId: 'msg-1',
          modelId: 'model-x',
          conversationId: 'conv-1',
          contents: [TextContent('partial')],
        ),
        ChatResponseUpdate(
          role: ChatRole.assistant,
          finishReason: ChatFinishReason.stop,
          usage: usage,
          contents: [TextContent(' done')],
        ),
      ];

      // Act
      final response = updates.toChatResponse();

      // Assert
      expect(response.responseId, 'resp-1');
      expect(response.modelId, 'model-x');
      expect(response.conversationId, 'conv-1');
      expect(response.finishReason, ChatFinishReason.stop);
      expect(response.usage, same(usage));
      expect(response.messages.single.messageId, 'msg-1');
    });

    test('keeps last non-null value for response-level fields', () {
      // Arrange
      final updates = [
        ChatResponseUpdate(
          role: ChatRole.assistant,
          conversationId: 'conv-early',
          contents: [TextContent('a')],
        ),
        ChatResponseUpdate(
          role: ChatRole.assistant,
          contents: [TextContent('b')],
        ),
      ];

      // Act
      final response = updates.toChatResponse();

      // Assert: conversationId from the earlier update is not lost when the
      // final update omits it.
      expect(response.conversationId, 'conv-early');
    });

    test('returns an empty response for no updates', () {
      // Arrange
      final updates = <ChatResponseUpdate>[];

      // Act
      final response = updates.toChatResponse();

      // Assert
      expect(response.messages, isEmpty);
      expect(response.usage, isNull);
    });
  });
}
