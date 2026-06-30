// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

/// Thrown when a saved agent cannot be resolved into a runnable agent.
///
/// Typical causes are a missing source, model, or API key, or an attempt to
/// delete a configuration that other configurations still reference.
@immutable
class ConfiguredAgentException implements Exception {
  /// Creates a [ConfiguredAgentException] with a human-readable [message].
  const ConfiguredAgentException(this.message);

  /// Describes what went wrong, suitable for surfacing to the user.
  final String message;

  @override
  String toString() => 'ConfiguredAgentException: $message';
}
