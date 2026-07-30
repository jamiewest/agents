import 'dart:convert';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'prompt_log.dart';

/// A [ChatClient] decorator that records each outgoing request into a
/// [PromptLog] before delegating.
///
/// This sits at the boundary every provider shares, so it captures cloud API
/// requests the same way regardless of provider. The captured body is a
/// readable transcript of the request payload, not the exact HTTP JSON.
class PromptLoggingChatClient extends DelegatingChatClient {
  /// Wraps its inner client, logging each request into [log] under [title].
  PromptLoggingChatClient(
    super.inner, {
    required this.log,
    required this.title,
  });

  /// The unified prompt log this client writes to.
  final PromptLog log;

  /// Short label identifying the model/provider for captured entries.
  final String title;

  void _capture(Iterable<ChatMessage> messages, ChatOptions? options) {
    log.add(
      PromptLogEntry(
        title: title,
        body: renderRequest(messages, options),
        capturedAt: DateTime.now(),
        tags: _tagsFor(messages, options),
      ),
    );
  }

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    _capture(messages, options);
    return super.getResponse(
      messages: messages,
      options: options,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) {
    _capture(messages, options);
    return super.getStreamingResponse(
      messages: messages,
      options: options,
      cancellationToken: cancellationToken,
    );
  }

  static List<String> _tagsFor(
    Iterable<ChatMessage> messages,
    ChatOptions? options,
  ) {
    final tools = options?.tools ?? const <AITool>[];
    return <String>[
      '${messages.length} messages',
      if (tools.isNotEmpty) '${tools.length} tools',
      if (options?.temperature != null) 'temp ${options!.temperature}',
      if (options?.maxOutputTokens != null)
        'maxTokens ${options!.maxOutputTokens}',
    ];
  }
}

/// Renders a chat request as a readable transcript.
///
/// Shows the system instructions, the names of declared tools, and each
/// message's role and content (text, plus markers for images, tool calls, and
/// tool results). This mirrors what the provider actually sends.
String renderRequest(Iterable<ChatMessage> messages, ChatOptions? options) {
  final buf = StringBuffer();

  final instructions = options?.instructions?.trim();
  if (instructions != null && instructions.isNotEmpty) {
    buf
      ..writeln('[system instructions]')
      ..writeln(instructions)
      ..writeln();
  }

  final tools = options?.tools ?? const <AITool>[];
  if (tools.isNotEmpty) {
    final names = tools
        .map(
          (t) => t is AIFunctionDeclaration ? t.name : t.runtimeType.toString(),
        )
        .join(', ');
    buf
      ..writeln('[tools] $names')
      ..writeln();
  }

  for (final message in messages) {
    buf.writeln('[${message.role.value}]');
    final text = message.text.trim();
    if (text.isNotEmpty) buf.writeln(text);
    for (final content in message.contents) {
      if (content is DataContent && content.hasTopLevelMediaType('image')) {
        buf.writeln('(image)');
      } else if (content is FunctionCallContent) {
        buf.writeln(
          '(tool call ${content.name} ${jsonEncode(content.arguments ?? const <String, Object?>{})})',
        );
      } else if (content is FunctionResultContent) {
        buf.writeln('(tool result ${content.callId}: ${content.result})');
      }
    }
    buf.writeln();
  }

  return buf.toString().trimRight();
}
