// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal GGUF header for tests.
class _GgufBuilder {
  final BytesBuilder _bytes = BytesBuilder();

  _GgufBuilder header({int version = 3, required int kvCount}) {
    _u32(0x46554747); // 'GGUF' little-endian
    _u32(version);
    _u64(0); // tensor_count
    _u64(kvCount);
    return this;
  }

  _GgufBuilder stringKv(String key, String value) {
    _string(key);
    _u32(8); // string type
    _string(value);
    return this;
  }

  _GgufBuilder uint32Kv(String key, int value) {
    _string(key);
    _u32(4); // uint32 type
    _u32(value);
    return this;
  }

  _GgufBuilder arrayKv(String key, List<String> values) {
    _string(key);
    _u32(9); // array type
    _u32(8); // element type: string
    _u64(values.length);
    values.forEach(_string);
    return this;
  }

  Uint8List build() => _bytes.toBytes();

  void _string(String value) {
    final encoded = utf8.encode(value);
    _u64(encoded.length);
    _bytes.add(encoded);
  }

  void _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void _u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }
}

void main() {
  group('GgufMetadata.tryParse', () {
    test('reads architecture, name, and chat template', () {
      final bytes = _GgufBuilder()
          .header(kvCount: 5)
          .stringKv('general.architecture', 'qwen2')
          .uint32Kv('general.quantization_version', 2)
          .arrayKv('tokenizer.ggml.tokens', ['<s>', '</s>'])
          .stringKv('general.name', 'Qwen2.5 7B Instruct')
          .stringKv(
            'tokenizer.chat_template',
            '{% for m in messages %}<|im_start|>…<tool_call>…{% endfor %}',
          )
          .build();

      final metadata = GgufMetadata.tryParse(bytes);
      expect(metadata, isNotNull);
      expect(metadata!.architecture, 'qwen2');
      expect(metadata.name, 'Qwen2.5 7B Instruct');
      expect(metadata.chatTemplate, contains('<|im_start|>'));
    });

    test('accepts version 2 headers', () {
      final bytes = _GgufBuilder()
          .header(version: 2, kvCount: 1)
          .stringKv('general.architecture', 'gemma2')
          .build();

      expect(GgufMetadata.tryParse(bytes)?.architecture, 'gemma2');
    });

    test('salvages keys read before truncation', () {
      final full = _GgufBuilder()
          .header(kvCount: 3)
          .stringKv('general.architecture', 'lfm2')
          .stringKv('general.name', 'LFM2 1.2B')
          .stringKv('tokenizer.chat_template', 'x' * 4096)
          .build();
      final truncated = Uint8List.sublistView(full, 0, full.length - 2048);

      final metadata = GgufMetadata.tryParse(truncated);
      expect(metadata, isNotNull);
      expect(metadata!.architecture, 'lfm2');
      expect(metadata.name, 'LFM2 1.2B');
      expect(metadata.chatTemplate, isNull);
    });

    test('rejects non-GGUF bytes', () {
      expect(GgufMetadata.tryParse(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
        GgufMetadata.tryParse(Uint8List.fromList(List<int>.filled(64, 0x42))),
        isNull,
      );
      expect(GgufMetadata.tryParse(Uint8List(0)), isNull);
    });

    test('rejects unsupported versions', () {
      final v1 = _GgufBuilder().header(version: 1, kvCount: 0).build();
      expect(GgufMetadata.tryParse(v1), isNull);
    });
  });

  group('chatFormatFromGgufMetadata', () {
    GgufMetadata parse(_GgufBuilder builder) =>
        GgufMetadata.tryParse(builder.build())!;

    test('chat-template markers win over architecture', () {
      final metadata = parse(
        _GgufBuilder()
            .header(kvCount: 2)
            .stringKv('general.architecture', 'llama')
            .stringKv(
              'tokenizer.chat_template',
              '{{ "<|start_header_id|>" + role }}',
            ),
      );
      expect(chatFormatFromGgufMetadata(metadata), 'llama3');
    });

    test('template markers map each family', () {
      const templates = <String, String>{
        '<|tool_call_start|>': 'lfm2',
        '<start_of_turn>': 'gemma',
        '[INST]': 'mistral',
        '<tool_call>': 'qwen',
        '<|im_start|>': 'chatml',
      };
      templates.forEach((marker, expected) {
        final metadata = parse(
          _GgufBuilder()
              .header(kvCount: 1)
              .stringKv('tokenizer.chat_template', 'prefix $marker suffix'),
        );
        expect(chatFormatFromGgufMetadata(metadata), expected);
      });
    });

    test('falls back to architecture', () {
      final metadata = parse(
        _GgufBuilder()
            .header(kvCount: 1)
            .stringKv('general.architecture', 'qwen3'),
      );
      expect(chatFormatFromGgufMetadata(metadata), 'qwen');
    });

    test('bare llama architecture is ambiguous', () {
      final metadata = parse(
        _GgufBuilder()
            .header(kvCount: 1)
            .stringKv('general.architecture', 'llama'),
      );
      expect(chatFormatFromGgufMetadata(metadata), isNull);
    });
  });
}
