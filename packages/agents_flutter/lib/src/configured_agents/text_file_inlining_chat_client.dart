// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

/// Rewrites text-like file attachments into prompt text before a model call.
///
/// Chat UIs attach files as [DataContent], but only some providers accept
/// arbitrary file bytes: Gemini takes inline documents, while OpenAI-style
/// Chat Completions and local llama.cpp models understand images at most —
/// an attached CSV or source file would be silently dropped. Every model can
/// read plain text, so this decorator converts each text-like [DataContent]
/// (`text/*`, JSON, XML, YAML, and friends) into a [TextContent] block that
/// carries the file name and media type.
///
/// Apply it as the innermost decorator, directly around the provider client,
/// so layers above it — chat-history persistence in particular — still see
/// the original [DataContent] and durable transcripts keep real attachments.
/// Messages are cloned before rewriting; the caller's history is never
/// mutated. Non-text attachments (images, PDFs, audio) pass through
/// untouched for the provider mapping to handle.
class TextFileInliningChatClient extends DelegatingChatClient {
  /// Wraps [innerClient], inlining text-like file attachments on the way in.
  TextFileInliningChatClient(super.innerClient);

  /// Media types treated as text besides the `text/` top-level type.
  static const Set<String> _textApplicationTypes = <String>{
    'application/json',
    'application/xml',
    'application/yaml',
    'application/x-yaml',
    'application/javascript',
    'application/typescript',
    'application/csv',
    'application/sql',
    'application/x-sh',
  };

  /// Whether [mediaType] identifies content safe to decode as text.
  static bool isTextLike(String? mediaType) {
    if (mediaType == null) return false;
    final normalized = mediaType.split(';').first.trim().toLowerCase();
    return normalized.startsWith('text/') ||
        _textApplicationTypes.contains(normalized) ||
        normalized.endsWith('+json') ||
        normalized.endsWith('+xml');
  }

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) => innerClient.getResponse(
    messages: _inlineTextFiles(messages),
    options: options,
    cancellationToken: cancellationToken,
  );

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) => innerClient.getStreamingResponse(
    messages: _inlineTextFiles(messages),
    options: options,
    cancellationToken: cancellationToken,
  );

  List<ChatMessage> _inlineTextFiles(Iterable<ChatMessage> messages) =>
      <ChatMessage>[
        for (final message in messages)
          message.contents.any(_isInlinableTextFile)
              ? _inlineMessage(message)
              : message,
      ];

  static bool _isInlinableTextFile(AIContent content) =>
      content is DataContent &&
      content.data != null &&
      isTextLike(content.mediaType);

  /// Returns a copy of [message] with text-like file bytes replaced by
  /// [TextContent]; [ChatMessage.clone] copies the contents list, so the
  /// original message stays intact.
  static ChatMessage _inlineMessage(ChatMessage message) {
    final clone = message.clone();
    for (var i = 0; i < clone.contents.length; i++) {
      final content = clone.contents[i];
      if (_isInlinableTextFile(content)) {
        clone.contents[i] = TextContent(_fileAsText(content as DataContent));
      }
    }
    return clone;
  }

  static String _fileAsText(DataContent content) {
    final text = utf8.decode(content.data!, allowMalformed: true);
    final name = content.name ?? 'attachment';
    final mediaType = content.mediaType ?? 'text/plain';
    return '<attached-file name="$name" media-type="$mediaType">\n'
        '$text\n'
        '</attached-file>';
  }
}
