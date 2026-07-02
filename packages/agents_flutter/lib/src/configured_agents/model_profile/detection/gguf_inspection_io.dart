// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'gguf_metadata.dart';

/// Reads and parses the GGUF header of the file at [path].
///
/// At most [maxPrefixBytes] are read — GGUF metadata precedes tensor
/// data, so the default 8 MiB covers even large embedded chat templates.
/// Returns `null` when the file cannot be read or is not GGUF; never
/// throws.
Future<GgufMetadata?> readGgufMetadata(
  String path, {
  int maxPrefixBytes = 8 * 1024 * 1024,
}) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final length = await file.length();
    final toRead = length < maxPrefixBytes ? length : maxPrefixBytes;
    final bytes = await file.read(toRead);
    return GgufMetadata.tryParse(Uint8List.fromList(bytes));
  } on Object {
    return null;
  } finally {
    await file?.close();
  }
}
