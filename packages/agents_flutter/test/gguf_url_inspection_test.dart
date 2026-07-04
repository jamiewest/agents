// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Builds a minimal GGUF header carrying one chat-template string.
Uint8List _ggufBytes(String template) {
  final bytes = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    u64(encoded.length);
    bytes.add(encoded);
  }

  u32(0x46554747); // 'GGUF'
  u32(3); // version
  u64(0); // tensor_count
  u64(1); // kv_count
  string('tokenizer.chat_template');
  u32(8); // string type
  string(template);
  return bytes.toBytes();
}

/// Serves [body] in fixed-size chunks and records how much was consumed.
final class _ChunkedClient extends http.BaseClient {
  _ChunkedClient(this.body, {this.statusCode = 200, this.chunkSize = 1024});

  final Uint8List body;
  final int statusCode;
  final int chunkSize;
  http.BaseRequest? lastRequest;
  int chunksDelivered = 0;
  bool cancelled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final controller = StreamController<List<int>>();
    var offset = 0;
    void push() {
      if (controller.isClosed) return;
      if (offset >= body.length) {
        controller.close();
        return;
      }
      final end = (offset + chunkSize).clamp(0, body.length);
      controller.add(Uint8List.sublistView(body, offset, end));
      offset = end;
      chunksDelivered++;
      scheduleMicrotask(push);
    }

    controller.onListen = push;
    controller.onCancel = () {
      cancelled = true;
    };
    return http.StreamedResponse(controller.stream, statusCode);
  }
}

void main() {
  test('parses metadata from a ranged fetch', () async {
    final client = _ChunkedClient(_ggufBytes('x <start_of_turn> y'));

    final metadata = await readGgufMetadataFromUrl(
      Uri.parse('https://models.example/model.gguf'),
      client: client,
    );

    expect(metadata, isNotNull);
    expect(chatFormatFromGgufMetadata(metadata!), 'gemma');
    expect(client.lastRequest!.headers['Range'], startsWith('bytes=0-'));
  });

  test('stops reading when a server ignores Range', () async {
    // A "file" much larger than the sniff limit: the reader must cancel
    // the transfer instead of consuming it all.
    final header = _ggufBytes('<|im_start|>');
    final body = BytesBuilder()
      ..add(header)
      ..add(Uint8List(4 * 1024 * 1024));
    final client = _ChunkedClient(body.toBytes(), chunkSize: 64 * 1024);

    final metadata = await readGgufMetadataFromUrl(
      Uri.parse('https://models.example/model.gguf'),
      client: client,
      maxPrefixBytes: 256 * 1024,
    );

    expect(metadata, isNotNull);
    expect(chatFormatFromGgufMetadata(metadata!), 'chatml');
    expect(client.cancelled, isTrue);
    // 256 KiB limit at 64 KiB chunks: it should stop right at the limit.
    expect(client.chunksDelivered, lessThanOrEqualTo(5));
  });

  test('returns null on an error status', () async {
    final client = _ChunkedClient(_ggufBytes('<|im_start|>'), statusCode: 404);

    expect(
      await readGgufMetadataFromUrl(
        Uri.parse('https://models.example/missing.gguf'),
        client: client,
      ),
      isNull,
    );
  });

  test('returns null for non-GGUF bytes', () async {
    final client = _ChunkedClient(
      Uint8List.fromList(utf8.encode('<html>not a model</html>')),
    );

    expect(
      await readGgufMetadataFromUrl(
        Uri.parse('https://models.example/model.gguf'),
        client: client,
      ),
      isNull,
    );
  });

  test('sniffGgufMetadata routes URLs through the ranged reader', () async {
    final client = _ChunkedClient(_ggufBytes('[INST]'));

    final metadata = await sniffGgufMetadata(
      'https://models.example/model.gguf',
      client: client,
    );

    expect(metadata, isNotNull);
    expect(chatFormatFromGgufMetadata(metadata!), 'mistral');
  });
}
