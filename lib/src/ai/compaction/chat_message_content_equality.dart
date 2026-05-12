import 'package:extensions/ai.dart';

/// Content-based equality comparison for [ChatMessage] instances.
extension ChatMessageContentEquality on ChatMessage? {
  /// Determines whether two [ChatMessage] instances represent the same message
  /// by content.
  ///
  /// When both messages define a message ID, identity is determined solely by
  /// that identifier. Otherwise, the comparison falls through to role, author
  /// name, and each item in contents.
  bool contentEquals(ChatMessage? other) {
    final message = this;
    if (identical(message, other)) {
      return true;
    }
    if (message == null || other == null) {
      return false;
    }
    if (message.messageId != null && other.messageId != null) {
      return message.messageId == other.messageId;
    }
    if (message.role != other.role) {
      return false;
    }
    if (message.authorName != other.authorName) {
      return false;
    }
    return contentsEqual(message.contents, other.contents);
  }

  static bool contentsEqual(Iterable<AIContent>? a, Iterable<AIContent>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    final listA = a.toList();
    final listB = b.toList();
    if (listA.length != listB.length) return false;
    for (var i = 0; i < listA.length; i++) {
      if (!_contentEquals(listA[i], listB[i])) return false;
    }
    return true;
  }

  static bool _contentEquals(AIContent a, AIContent b) {
    if (identical(a, b)) return true;
    if (a.runtimeType != b.runtimeType) return false;

    return switch ((a, b)) {
      (TextContent(:final text), TextContent(text: final otherText)) =>
        text == otherText,
      (
        TextReasoningContent(
          text: final text,
          protectedData: final protectedData,
        ),
        TextReasoningContent(
          text: final otherText,
          protectedData: final otherProtectedData,
        ),
      ) =>
        text == otherText && _listEquals(protectedData, otherProtectedData),
      (
        FunctionCallContent(
          callId: final callId,
          name: final name,
          arguments: final arguments,
        ),
        FunctionCallContent(
          callId: final otherCallId,
          name: final otherName,
          arguments: final otherArguments,
        ),
      ) =>
        callId == otherCallId &&
            name == otherName &&
            _mapEquals(arguments, otherArguments),
      (
        FunctionResultContent(callId: final callId, result: final result),
        FunctionResultContent(
          callId: final otherCallId,
          result: final otherResult,
        ),
      ) =>
        callId == otherCallId && result?.toString() == otherResult?.toString(),
      (
        DataContent(
          data: final data,
          mediaType: final mediaType,
          name: final name,
          uri: final uri,
        ),
        DataContent(
          data: final otherData,
          mediaType: final otherMediaType,
          name: final otherName,
          uri: final otherUri,
        ),
      ) =>
        _listEquals(data, otherData) &&
            mediaType == otherMediaType &&
            name == otherName &&
            uri == otherUri,
      (
        UriContent(:final uri, :final mediaType),
        UriContent(uri: final otherUri, mediaType: final otherMediaType),
      ) =>
        uri == otherUri && mediaType == otherMediaType,
      (
        ErrorContent(
          message: final message,
          errorCode: final errorCode,
          details: final details,
        ),
        ErrorContent(
          message: final otherMessage,
          errorCode: final otherErrorCode,
          details: final otherDetails,
        ),
      ) =>
        message == otherMessage &&
            errorCode == otherErrorCode &&
            details == otherDetails,
      (
        HostedFileContent(
          fileId: final fileId,
          mediaType: final mediaType,
          name: final name,
        ),
        HostedFileContent(
          fileId: final otherFileId,
          mediaType: final otherMediaType,
          name: final otherName,
        ),
      ) =>
        fileId == otherFileId &&
            mediaType == otherMediaType &&
            name == otherName,
      _ => a == b,
    };
  }

  static bool _listEquals(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          b[entry.key]?.toString() != entry.value?.toString()) {
        return false;
      }
    }
    return true;
  }
}
