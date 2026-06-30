/// Resolves a configured `llama.format` name to its [ChatFormat].
///
/// This is the single source of truth shared by the host app (which builds a
/// chat client) and its model-editor UI (which validates the name), so the two
/// can never drift. Add a new family here and both pick it up.
library;

import 'chat_format.dart';
import 'chatml/chatml_chat_format.dart';
import 'gemma/gemma_chat_format.dart';
import 'lfm2/lfm2_chat_format.dart';
import 'llama3/llama3_chat_format.dart';
import 'mistral/mistral_chat_format.dart';
import 'qwen/qwen_chat_format.dart';

/// The name used when `llama.format` is unset, for backwards compatibility.
const String defaultChatFormatName = 'gemma';

/// All known `llama.format` names mapped to their [ChatFormat].
///
/// `lfm2` and `lfm2-vl` both resolve to [Lfm2ChatFormat] (one wire format, two
/// checkpoints).
const Map<String, ChatFormat> _formats = <String, ChatFormat>{
  'gemma': GemmaChatFormat(),
  'lfm2': Lfm2ChatFormat(),
  'lfm2-vl': Lfm2ChatFormat(),
  'chatml': ChatmlChatFormat(),
  'llama3': Llama3ChatFormat(),
  'mistral': MistralChatFormat(),
  'qwen': QwenChatFormat(),
};

/// The set of accepted `llama.format` names (an empty string is also accepted
/// and resolves to [defaultChatFormatName]).
Set<String> get supportedChatFormatNames => _formats.keys.toSet();

/// Resolves [name] to a [ChatFormat], or `null` when [name] is unknown.
///
/// A null or empty [name] resolves to [defaultChatFormatName].
ChatFormat? resolveChatFormat(String? name) {
  final key = (name == null || name.isEmpty) ? defaultChatFormatName : name;
  return _formats[key];
}
