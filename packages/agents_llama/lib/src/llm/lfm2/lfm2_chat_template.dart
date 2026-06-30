/// LFM2 / LFM2-VL prompt rendering for on-device llama.cpp inference.
///
/// Ported from two authoritative upstream Jinja templates:
///   * Text + image turns follow `LiquidAI/LFM2-VL-1.6B`'s
///     `chat_template.jinja` (ChatML: `<|im_start|>role\n…<|im_end|>\n`, with
///     image parts rendered as a media marker).
///   * Tool declarations, tool calls and tool responses follow
///     `LiquidAI/LFM2-1.2B`'s `chat_template.jinja` (the VL default template
///     omits tools, but the VL tokenizer carries all six tool tokens, so the
///     text model's convention applies). Tool definitions and responses are
///     JSON; tool calls are Pythonic — `[name(arg="value")]`.
///
/// Two conventions match [GemmaChatTemplate]:
///   * No `<|startoftext|>` (BOS) is emitted — the native tokenizer adds it
///     (`add_bos_token: true`), so emitting it here too would double it.
///   * Image parts emit `<__media__>` (`GemmaChatTemplate.mediaMarker`), the
///     generic mtmd marker the runtime substitutes with the model's image
///     tokens; the raw jinja literal `<image>` is the post-substitution form.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:extensions/ai.dart';

import '../gemma/gemma_chat_template.dart' show GemmaChatTemplate;

/// A rendered LFM2 prompt plus the stop sequences generation should halt on.
class Lfm2Prompt {
  const Lfm2Prompt({
    required this.text,
    required this.stopSequences,
    this.images = const <Uint8List>[],
  });

  /// The formatted prompt, ready to pass to `LlamaFlutter.generate`.
  final String text;

  /// Strings that terminate a generation turn. See
  /// [Lfm2ChatTemplate.stopSequences].
  final List<String> stopSequences;

  /// Image bytes referenced by the media markers embedded in [text], in the
  /// order the markers appear. Empty for a text-only prompt.
  final List<Uint8List> images;
}

/// The parsed result of one generated model turn.
class Lfm2Turn {
  const Lfm2Turn({required this.text, required this.calls});

  /// User-visible prose, with tool-call markup removed.
  final String text;

  /// Tool calls the model requested, in emission order. Empty for a plain
  /// answer.
  final List<FunctionCallContent> calls;
}

/// Renders LFM2 prompts from M.E.AI chat messages and tool declarations.
class Lfm2ChatTemplate {
  const Lfm2ChatTemplate();

  // Control tokens.
  static const String imStart = '<|im_start|>';
  static const String imEnd = '<|im_end|>';
  static const String toolListStart = '<|tool_list_start|>';
  static const String toolListEnd = '<|tool_list_end|>';
  static const String toolCallStart = '<|tool_call_start|>';
  static const String toolCallEnd = '<|tool_call_end|>';
  static const String toolResponseStart = '<|tool_response_start|>';
  static const String toolResponseEnd = '<|tool_response_end|>';

  /// mtmd's default media marker, reused from the Gemma template. One is
  /// emitted per attached image; the runtime substitutes the model's image
  /// tokens.
  static const String mediaMarker = GemmaChatTemplate.mediaMarker;

  /// Stop sequences a caller passes to generation.
  ///
  /// `<|im_end|>` ends every turn (it is also the model's EOS). A tool-call
  /// turn emits `<|tool_call_start|>…<|tool_call_end|>` and then `<|im_end|>`,
  /// so stopping here captures the whole call block intact.
  static const List<String> stopSequences = <String>[imEnd];

  /// Renders [messages] (with optional [tools]) into an LFM2 prompt.
  ///
  /// [enableThinking] is ignored — LFM2's default template has no reasoning
  /// channel. When [addGenerationPrompt] is true a trailing
  /// `<|im_start|>assistant\n` is appended.
  Lfm2Prompt render(
    Iterable<ChatMessage> messages, {
    Iterable<AIFunctionDeclaration> tools = const <AIFunctionDeclaration>[],
    bool enableThinking = false,
    bool addGenerationPrompt = true,
  }) {
    final all = messages.toList();
    final toolList = tools.toList();
    final out = StringBuffer();
    final images = <Uint8List>[];

    // System turn: an explicit leading system message and/or the tool list.
    var loopStart = 0;
    final system = StringBuffer();
    if (all.isNotEmpty && _roleOf(all.first) == 'system') {
      system.write(all.first.text);
      loopStart = 1;
    }
    if (toolList.isNotEmpty) {
      if (system.isNotEmpty) system.write('\n');
      system
        ..write('List of tools: ')
        ..write(toolListStart)
        ..write('[')
        ..write(toolList.map(_formatDeclaration).join(', '))
        ..write(']')
        ..write(toolListEnd);
    }
    if (system.isNotEmpty) {
      out
        ..write(imStart)
        ..write('system\n')
        ..write(system)
        ..write(imEnd)
        ..write('\n');
    }

    for (final msg in all.sublist(loopStart)) {
      final role = _roleOf(msg);
      out
        ..write(imStart)
        ..write(role)
        ..write('\n')
        ..write(_contentFor(msg, role, images))
        ..write(imEnd)
        ..write('\n');
    }

    if (addGenerationPrompt) {
      out
        ..write(imStart)
        ..write('assistant\n');
    }

    return Lfm2Prompt(
      text: out.toString(),
      stopSequences: stopSequences,
      images: images,
    );
  }

  /// Builds the body of one `<|im_start|>role\n…<|im_end|>` turn.
  String _contentFor(ChatMessage msg, String role, List<Uint8List> images) {
    if (role == 'tool') {
      final results = msg.contents.whereType<FunctionResultContent>().toList();
      final value = results.length == 1
          ? results.first.result
          : results.map((r) => r.result).toList();
      // Matches the jinja: a bare string result is emitted raw; anything else
      // is JSON-encoded (`content | tojson`).
      final encoded = value is String ? value : _jsonEncode(value);
      return '$toolResponseStart$encoded$toolResponseEnd';
    }

    final buf = StringBuffer();
    for (final content in msg.contents) {
      if (content is TextContent) {
        buf.write(content.text);
      } else if (content is DataContent &&
          content.data != null &&
          content.hasTopLevelMediaType('image')) {
        images.add(content.data!);
        buf.write(mediaMarker);
      }
    }

    final calls = msg.contents.whereType<FunctionCallContent>().toList();
    if (calls.isNotEmpty) {
      buf
        ..write(toolCallStart)
        ..write('[')
        ..write(calls.map(_formatCall).join(', '))
        ..write(']')
        ..write(toolCallEnd);
    }
    return buf.toString();
  }

  /// Parses one raw generated model turn into prose plus any tool calls.
  ///
  /// [generated] is the text emitted for a single model turn with the
  /// `<|im_end|>` stop sequence already stripped, so any
  /// `<|tool_call_start|>…<|tool_call_end|>` block is complete. Synthetic
  /// sequential [FunctionCallContent.callId]s are assigned so results can be
  /// correlated downstream.
  Lfm2Turn parse(String generated) {
    final calls = <FunctionCallContent>[];
    final text = StringBuffer();
    var cursor = 0;
    while (cursor < generated.length) {
      final open = generated.indexOf(toolCallStart, cursor);
      if (open < 0) {
        text.write(generated.substring(cursor));
        break;
      }
      text.write(generated.substring(cursor, open));
      final close = generated.indexOf(toolCallEnd, open);
      final bodyEnd = close < 0 ? generated.length : close;
      final block = generated.substring(open + toolCallStart.length, bodyEnd);
      _PyCallParser(block, calls.length).parseInto(calls);
      cursor = close < 0 ? generated.length : close + toolCallEnd.length;
    }
    return Lfm2Turn(text: text.toString().trim(), calls: calls);
  }

  // --- rendering helpers ---

  String _roleOf(ChatMessage m) => m.role.value;

  /// Renders one tool declaration as the JSON object LFM2 expects:
  /// `{"name": …, "description": …, "parameters": {…}}`.
  String _formatDeclaration(AIFunctionDeclaration tool) =>
      _jsonEncode(<String, Object?>{
        'name': tool.name,
        'description': tool.description ?? '',
        if (tool.parametersSchema != null) 'parameters': tool.parametersSchema,
      });

  /// Renders one assistant tool call in Pythonic form: `name(arg="value")`.
  String _formatCall(FunctionCallContent call) {
    final args = call.arguments ?? const <String, Object?>{};
    final parts = args.entries.map((e) => '${e.key}=${_pyLiteral(e.value)}');
    return '${call.name}(${parts.join(', ')})';
  }

  /// JSON with Python `json.dumps` default separators (`, ` and `: `) to match
  /// the upstream jinja `tojson` filter the model was trained on.
  static String _jsonEncode(Object? value) {
    if (value is Map) {
      final parts = value.entries.map(
        (e) => '${jsonEncode(e.key.toString())}: ${_jsonEncode(e.value)}',
      );
      return '{${parts.join(', ')}}';
    }
    if (value is Iterable) {
      return '[${value.map(_jsonEncode).join(', ')}]';
    }
    return jsonEncode(value);
  }

  /// Renders a value as a Python literal for a tool-call argument.
  static String _pyLiteral(Object? value) {
    if (value == null) return 'None';
    if (value is bool) return value ? 'True' : 'False';
    if (value is num) return value.toString();
    if (value is String) return jsonEncode(value);
    if (value is Map) {
      final parts = value.entries.map(
        (e) => '${jsonEncode(e.key.toString())}: ${_pyLiteral(e.value)}',
      );
      return '{${parts.join(', ')}}';
    }
    if (value is Iterable) {
      return '[${value.map(_pyLiteral).join(', ')}]';
    }
    return jsonEncode(value.toString());
  }
}

/// Recursive-descent reader for LFM2's Pythonic tool-call list.
///
/// Parses `[name(arg="s", n=1, flag=True, items=[1,2])]` — one or more calls
/// of the form `name(key=value, …)`. Values are Python literals: strings
/// (`"…"` or `'…'`), numbers, `True`/`False`/`None`, lists and dicts. Throws
/// [FormatException] on malformed input so the decoder can fall back to raw
/// text.
class _PyCallParser {
  _PyCallParser(this._source, this._startIndex);

  final String _source;
  final int _startIndex;
  int _pos = 0;

  /// Parses the call list and appends each call to [calls].
  void parseInto(List<FunctionCallContent> calls) {
    _skipWs();
    _expect('[');
    _skipWs();
    if (_peek() == ']') {
      _pos++;
      return;
    }
    while (true) {
      calls.add(_parseCall(_startIndex + calls.length));
      _skipWs();
      final c = _peek();
      if (c == ',') {
        _pos++;
        _skipWs();
        continue;
      }
      _expect(']');
      break;
    }
  }

  FunctionCallContent _parseCall(int index) {
    final name = _parseIdentifier();
    _skipWs();
    _expect('(');
    final args = <String, Object?>{};
    _skipWs();
    if (_peek() != ')') {
      while (true) {
        _skipWs();
        final key = _parseIdentifier();
        _skipWs();
        _expect('=');
        _skipWs();
        args[key] = _parseValue();
        _skipWs();
        if (_peek() == ',') {
          _pos++;
          continue;
        }
        break;
      }
    }
    _skipWs();
    _expect(')');
    return FunctionCallContent(
      callId: 'call_$index',
      name: name,
      arguments: args,
    );
  }

  String _parseIdentifier() {
    final start = _pos;
    while (_pos < _source.length && _isIdentChar(_source[_pos])) {
      _pos++;
    }
    if (_pos == start) {
      throw FormatException('Expected identifier at $_pos', _source, _pos);
    }
    return _source.substring(start, _pos);
  }

  Object? _parseValue() {
    final c = _peek();
    if (c == '"' || c == "'") return _parseString(c);
    if (c == '[') return _parseList();
    if (c == '{') return _parseDict();
    return _parseLiteral();
  }

  String _parseString(String quote) {
    _pos++;
    final buf = StringBuffer();
    while (_pos < _source.length) {
      final ch = _source[_pos];
      if (ch == '\\' && _pos + 1 < _source.length) {
        final next = _source[_pos + 1];
        buf.write(_unescape(next));
        _pos += 2;
        continue;
      }
      if (ch == quote) {
        _pos++;
        return buf.toString();
      }
      buf.write(ch);
      _pos++;
    }
    throw FormatException('Unterminated string at $_pos', _source, _pos);
  }

  String _unescape(String c) {
    switch (c) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      default:
        return c;
    }
  }

  List<Object?> _parseList() {
    _expect('[');
    final list = <Object?>[];
    _skipWs();
    if (_peek() == ']') {
      _pos++;
      return list;
    }
    while (true) {
      _skipWs();
      list.add(_parseValue());
      _skipWs();
      if (_peek() == ',') {
        _pos++;
        continue;
      }
      _expect(']');
      break;
    }
    return list;
  }

  Map<String, Object?> _parseDict() {
    _expect('{');
    final map = <String, Object?>{};
    _skipWs();
    if (_peek() == '}') {
      _pos++;
      return map;
    }
    while (true) {
      _skipWs();
      final keyChar = _peek();
      final key = (keyChar == '"' || keyChar == "'")
          ? _parseString(keyChar)
          : _parseIdentifier();
      _skipWs();
      _expect(':');
      _skipWs();
      map[key] = _parseValue();
      _skipWs();
      if (_peek() == ',') {
        _pos++;
        continue;
      }
      _expect('}');
      break;
    }
    return map;
  }

  Object? _parseLiteral() {
    final start = _pos;
    while (_pos < _source.length && !',)]}'.contains(_source[_pos])) {
      _pos++;
    }
    final raw = _source.substring(start, _pos).trim();
    switch (raw) {
      case 'True':
        return true;
      case 'False':
        return false;
      case 'None':
        return null;
    }
    return num.tryParse(raw) ?? raw;
  }

  bool _isIdentChar(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || // A-Z
        (u >= 97 && u <= 122) || // a-z
        (u >= 48 && u <= 57) || // 0-9
        c == '_';
  }

  void _skipWs() {
    while (_pos < _source.length && _source[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  String _peek() => _pos < _source.length ? _source[_pos] : '';

  void _expect(String char) {
    if (_peek() != char) {
      throw FormatException('Expected "$char" at $_pos', _source, _pos);
    }
    _pos++;
  }
}
