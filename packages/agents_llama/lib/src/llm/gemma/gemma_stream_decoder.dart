/// Splits a raw Gemma token stream into Microsoft.Extensions.AI updates.
library;

import 'package:extensions/ai.dart';

import 'gemma_chat_template.dart';

/// Turns the `Stream<String>` from `LlamaFlutter.generate` into a stream of
/// [ChatResponseUpdate]s for an M.E.AI chat client.
///
/// Three kinds of content are separated as they stream in:
///   * **Thinking** — when thinking is enabled the model opens its turn with a
///     `<|channel>thought\n…\n<channel|>` block (see the Gemma 4 prompt format).
///     Its contents are emitted as [TextReasoningContent], with the `<|channel>`
///     markers and the `thought` label stripped.
///   * **Prose** — ordinary answer text, emitted as [TextContent].
///   * **Tool calls** — the first `<|tool_call>` marker flips the decoder into
///     buffering mode: everything from the marker onward is accumulated and,
///     when the stream ends, parsed into [FunctionCallContent] via
///     [GemmaChatTemplate.parse].
///
/// Text and tool calls are emitted in **separate** updates on purpose:
/// `FunctionInvokingChatClient` suppresses any update that carries a function
/// call, so combining them in one update would drop the prose.
class GemmaStreamDecoder {
  const GemmaStreamDecoder([this.template = const GemmaChatTemplate()]);

  final GemmaChatTemplate template;

  static const String _channelOpen = GemmaChatTemplate.channelOpen;
  static const String _channelClose = GemmaChatTemplate.channelClose;
  static const String _callOpen = GemmaChatTemplate.toolCallOpen;

  /// The thinking channel always carries the `thought` label right after
  /// `<|channel>`; it is dropped from the surfaced reasoning text.
  static const String _thoughtLabel = 'thought';

  Stream<ChatResponseUpdate> decode(Stream<String> tokens) async* {
    // Hold back the longest-marker-minus-one trailing chars so a marker that
    // straddles two pieces is never emitted as content.
    final holdback =
        <int>[
          _channelOpen.length,
          _channelClose.length,
          _callOpen.length,
        ].reduce((a, b) => a > b ? a : b) -
        1;

    var buf = '';
    final tail = StringBuffer();
    var thinking = false;
    var buffering = false;
    var labelPending = false;

    await for (final piece in tokens) {
      if (buffering) {
        tail.write(piece);
        continue;
      }
      buf += piece;

      var progressed = true;
      while (progressed) {
        progressed = false;

        if (thinking) {
          // Drop the leading `thought` label once we have enough to see it
          // whole (or the channel has already closed).
          if (labelPending) {
            if (buf.length > _thoughtLabel.length ||
                buf.contains(_channelClose)) {
              buf = _stripLabel(buf);
              labelPending = false;
              progressed = true;
              continue;
            }
            break;
          }

          final closeAt = buf.indexOf(_channelClose);
          if (closeAt >= 0) {
            final reasoning = buf.substring(0, closeAt);
            if (reasoning.isNotEmpty) yield _reasoning(reasoning);
            buf = buf.substring(closeAt + _channelClose.length);
            thinking = false;
            progressed = true;
            continue;
          }
          if (buf.length > holdback) {
            final emit = buf.substring(0, buf.length - holdback);
            if (emit.isNotEmpty) yield _reasoning(emit);
            buf = buf.substring(buf.length - holdback);
          }
          break;
        }

        final openAt = buf.indexOf(_channelOpen);
        final callAt = buf.indexOf(_callOpen);

        if (callAt >= 0 && (openAt < 0 || callAt <= openAt)) {
          final prose = buf.substring(0, callAt);
          if (prose.isNotEmpty) yield _text(prose);
          tail.write(buf.substring(callAt));
          buf = '';
          buffering = true;
          break;
        }
        if (openAt >= 0) {
          final prose = buf.substring(0, openAt);
          if (prose.isNotEmpty) yield _text(prose);
          buf = buf.substring(openAt + _channelOpen.length);
          thinking = true;
          labelPending = true;
          progressed = true;
          continue;
        }
        if (buf.length > holdback) {
          final emit = buf.substring(0, buf.length - holdback);
          if (emit.isNotEmpty) yield _text(emit);
          buf = buf.substring(buf.length - holdback);
        }
        break;
      }
    }

    if (buffering) {
      // A truncated or malformed tool call (e.g. the run hit maxTokens
      // mid-call) must not error the whole turn; surface the raw tail as
      // text instead so the user sees what the model produced.
      GemmaTurn turn;
      try {
        turn = template.parse(tail.toString());
      } on FormatException {
        yield _text(tail.toString());
        return;
      }
      if (turn.text.isNotEmpty) yield _text(turn.text);
      if (turn.calls.isNotEmpty) {
        yield ChatResponseUpdate(
          role: ChatRole.assistant,
          contents: List<AIContent>.of(turn.calls),
        );
      }
    } else if (thinking) {
      if (labelPending) buf = _stripLabel(buf);
      if (buf.isNotEmpty) yield _reasoning(buf);
    } else if (buf.isNotEmpty) {
      yield _text(buf);
    }
  }

  static final RegExp _labelPattern = RegExp(
    '^\\s*$_thoughtLabel[ \\t]*\\r?\\n?',
  );

  static String _stripLabel(String s) {
    final match = _labelPattern.firstMatch(s);
    return match == null ? s : s.substring(match.end);
  }

  static ChatResponseUpdate _text(String text) =>
      ChatResponseUpdate.fromText(ChatRole.assistant, text);

  static ChatResponseUpdate _reasoning(String text) => ChatResponseUpdate(
    role: ChatRole.assistant,
    contents: <AIContent>[TextReasoningContent(text)],
  );
}
