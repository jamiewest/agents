// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Reads GGUF metadata from a local model file where the platform allows.
///
/// On native platforms this reads a bounded prefix of the file and parses
/// it with `GgufMetadata.tryParse`; on the web (where model files are
/// object URLs) it always returns `null` and callers fall back to
/// name-based heuristics.
library;

export 'gguf_inspection_stub.dart'
    if (dart.library.io) 'gguf_inspection_io.dart';
