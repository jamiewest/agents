// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

/// The metadata keys read from a GGUF header for format detection.
///
/// Parsed from a bounded prefix of the file — GGUF stores all metadata
/// key/value pairs before tensor data, so a few megabytes is enough.
/// Pure Dart and byte-oriented (no `dart:io`) so it works on all
/// platforms; reading the file prefix is the caller's job.
final class GgufMetadata {
  const GgufMetadata._({this.architecture, this.chatTemplate, this.name});

  /// The `general.architecture` value (e.g. `qwen2`, `gemma3`, `llama`).
  final String? architecture;

  /// The `tokenizer.chat_template` Jinja source, when embedded.
  final String? chatTemplate;

  /// The `general.name` value.
  final String? name;

  /// Parses the GGUF header in [bytes].
  ///
  /// Returns `null` when [bytes] is not a GGUF v2/v3 header or is
  /// corrupt. A header merely truncated mid-metadata still yields
  /// whatever wanted keys were read before the cut. Never throws.
  static GgufMetadata? tryParse(Uint8List bytes) {
    final reader = _GgufReader(bytes);
    var validHeader = false;
    String? architecture;
    String? chatTemplate;
    String? name;
    try {
      if (reader.uint32() != 0x46554747) return null; // 'GGUF' LE
      final version = reader.uint32();
      if (version < 2 || version > 3) return null;
      reader.uint64(); // tensor_count
      final kvCount = reader.uint64();
      validHeader = true;

      for (var i = 0; i < kvCount; i++) {
        final key = reader.string();
        final type = reader.uint32();
        switch (key) {
          case 'general.architecture':
            architecture = reader.stringValueOrSkip(type);
          case 'tokenizer.chat_template':
            chatTemplate = reader.stringValueOrSkip(type);
          case 'general.name':
            name = reader.stringValueOrSkip(type);
          default:
            reader.skipValue(type);
        }
        if (architecture != null && chatTemplate != null && name != null) {
          break;
        }
      }
    } on _Truncated {
      // Keep whatever was read before the prefix ran out.
      if (!validHeader) return null;
    } on Object {
      return null;
    }
    return GgufMetadata._(
      architecture: architecture,
      chatTemplate: chatTemplate,
      name: name,
    );
  }
}

/// Maps parsed GGUF metadata to a chat-format name, or `null`.
///
/// Chat-template markers are the strongest signal; `general.architecture`
/// is the fallback. A bare `llama` architecture is ambiguous (it covers
/// many fine-tunes), so it is only mapped when the template also matches.
String? chatFormatFromGgufMetadata(GgufMetadata metadata) {
  final template = metadata.chatTemplate;
  if (template != null) {
    if (template.contains('<|start_header_id|>')) return 'llama3';
    if (template.contains('<|tool_call_start|>')) return 'lfm2';
    if (template.contains('<start_of_turn>')) return 'gemma';
    if (template.contains('[INST]')) return 'mistral';
    if (template.contains('<tool_call>')) return 'qwen';
    if (template.contains('<|im_start|>')) return 'chatml';
  }
  return switch (metadata.architecture) {
    'qwen2' || 'qwen3' || 'qwen3moe' => 'qwen',
    'gemma' || 'gemma2' || 'gemma3' => 'gemma',
    'lfm2' || 'lfm2moe' => 'lfm2',
    'phi2' || 'phi3' || 'smollm' => 'chatml',
    _ => null,
  };
}

/// Signals that the buffer ended before the value being read.
final class _Truncated implements Exception {
  const _Truncated();
}

/// A little-endian cursor over a GGUF header prefix.
final class _GgufReader {
  _GgufReader(Uint8List bytes)
    : _data = ByteData.sublistView(bytes),
      _length = bytes.length;

  final ByteData _data;
  final int _length;
  int _offset = 0;

  int uint32() {
    _ensure(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int uint64() {
    _ensure(8);
    final value = _data.getUint64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String string() {
    final length = uint64();
    _ensure(length);
    final value = utf8.decode(
      Uint8List.sublistView(_data, _offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }

  /// Reads a string value for a wanted key, or skips a non-string value.
  String? stringValueOrSkip(int type) {
    if (type != _typeString) {
      skipValue(type);
      return null;
    }
    return string();
  }

  void skipValue(int type) {
    switch (type) {
      case _typeUint8 || _typeInt8 || _typeBool:
        _skip(1);
      case _typeUint16 || _typeInt16:
        _skip(2);
      case _typeUint32 || _typeInt32 || _typeFloat32:
        _skip(4);
      case _typeUint64 || _typeInt64 || _typeFloat64:
        _skip(8);
      case _typeString:
        _skip(uint64());
      case _typeArray:
        final elementType = uint32();
        final count = uint64();
        for (var i = 0; i < count; i++) {
          skipValue(elementType);
        }
      default:
        throw const FormatException('Unknown GGUF value type');
    }
  }

  void _skip(int count) {
    _ensure(count);
    _offset += count;
  }

  void _ensure(int count) {
    if (count < 0 || _offset + count > _length) {
      throw const _Truncated();
    }
  }

  static const int _typeUint8 = 0;
  static const int _typeInt8 = 1;
  static const int _typeUint16 = 2;
  static const int _typeInt16 = 3;
  static const int _typeUint32 = 4;
  static const int _typeInt32 = 5;
  static const int _typeFloat32 = 6;
  static const int _typeBool = 7;
  static const int _typeString = 8;
  static const int _typeArray = 9;
  static const int _typeUint64 = 10;
  static const int _typeInt64 = 11;
  static const int _typeFloat64 = 12;
}
