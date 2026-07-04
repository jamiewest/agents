// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gguf_metadata.dart';

/// Reads and parses the GGUF header behind [url].
///
/// Sends a ranged GET for the metadata prefix. Servers that ignore the
/// `Range` header (and `blob:` object URLs, which have no ranges) stream
/// the whole file instead, so the body is read incrementally and the
/// transfer is cancelled the moment the prefix is in hand — a
/// multi-gigabyte model is never downloaded just to sniff its format.
///
/// Returns `null` when the fetch fails or the bytes are not GGUF; never
/// throws. Pass [client] to inject a fake transport in tests.
Future<GgufMetadata?> readGgufMetadataFromUrl(
  Uri url, {
  http.Client? client,
  int maxPrefixBytes = 8 * 1024 * 1024,
}) async {
  final transport = client ?? http.Client();
  try {
    final request = http.Request('GET', url)
      ..headers['Range'] = 'bytes=0-${maxPrefixBytes - 1}';
    final response = await transport.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final prefix = await _readPrefix(response.stream, maxPrefixBytes);
    if (prefix == null) return null;
    return GgufMetadata.tryParse(prefix);
  } on Object {
    return null;
  } finally {
    if (client == null) transport.close();
  }
}

/// Collects up to [maxBytes] from [stream], cancelling the subscription
/// (and with it the underlying transfer) once the limit is reached.
///
/// Returns whatever arrived before an error, or `null` when nothing did.
Future<Uint8List?> _readPrefix(Stream<List<int>> stream, int maxBytes) {
  final bytes = BytesBuilder(copy: false);
  final completer = Completer<Uint8List?>();
  late final StreamSubscription<List<int>> subscription;

  void finish() {
    if (completer.isCompleted) return;
    completer.complete(bytes.isEmpty ? null : bytes.takeBytes());
  }

  subscription = stream.listen(
    (chunk) {
      bytes.add(chunk);
      if (bytes.length >= maxBytes) {
        unawaited(subscription.cancel());
        finish();
      }
    },
    onDone: finish,
    onError: (Object _) => finish(),
    cancelOnError: true,
  );
  return completer.future;
}
