/// The LFM2 / LFM2-VL implementation of the model-family seam.
library;

import 'package:extensions/ai.dart';

import '../chat_format.dart';
import 'lfm2_chat_template.dart';
import 'lfm2_stream_decoder.dart';

/// LFM2's [ChatFormat]: [Lfm2ChatTemplate] rendering paired with
/// [Lfm2StreamDecoder] output splitting.
///
/// Covers the text and vision (LFM2-VL) variants — both speak the same ChatML
/// wire format; image parts are rendered as media markers the runtime
/// substitutes.
class Lfm2ChatFormat implements ChatFormat {
  const Lfm2ChatFormat();

  static const Lfm2ChatTemplate _template = Lfm2ChatTemplate();
  static const Lfm2StreamDecoder _decoder = Lfm2StreamDecoder();

  @override
  bool get supportsThinking => false;

  @override
  RenderedPrompt render(
    Iterable<ChatMessage> messages, {
    Iterable<AIFunctionDeclaration> tools = const <AIFunctionDeclaration>[],
    bool enableThinking = false,
  }) {
    final prompt = _template.render(messages, tools: tools);
    return RenderedPrompt(
      text: prompt.text,
      stopSequences: prompt.stopSequences,
      images: prompt.images,
    );
  }

  @override
  Stream<ChatResponseUpdate> decode(Stream<String> tokens) =>
      _decoder.decode(tokens);
}
