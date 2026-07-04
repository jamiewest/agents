// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Reads GGUF metadata from a local model file where the platform allows.
///
/// On native platforms this reads a bounded prefix of the file and parses
/// it with `GgufMetadata.tryParse`; on the web (where model files are
/// object URLs) the file reader always returns `null` — use
/// [sniffGgufMetadata], which routes URLs (including `blob:`) through the
/// ranged HTTP reader instead.
library;

import 'package:http/http.dart' as http;

import 'gguf_inspection_stub.dart'
    if (dart.library.io) 'gguf_inspection_io.dart'
    as file_reader;
import 'gguf_metadata.dart';
import 'gguf_url_inspection.dart';

export 'gguf_inspection_stub.dart'
    if (dart.library.io) 'gguf_inspection_io.dart';

/// Reads GGUF metadata from [source] — a file path, or an `http(s)`/`blob`
/// URL (the form a picked file takes on the web).
///
/// Returns `null` when the source cannot be read or is not GGUF; never
/// throws. Pass [client] to inject a fake transport in tests.
Future<GgufMetadata?> sniffGgufMetadata(String source, {http.Client? client}) {
  final uri = Uri.tryParse(source);
  if (uri != null && const {'http', 'https', 'blob'}.contains(uri.scheme)) {
    return readGgufMetadataFromUrl(uri, client: client);
  }
  return file_reader.readGgufMetadata(source);
}
