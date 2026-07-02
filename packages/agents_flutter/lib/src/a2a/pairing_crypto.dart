// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Token and credential helpers for A2A pairing.
///
/// Hosts persist only SHA-256 hashes of issued bearers and compare them in
/// constant time; consumers keep the raw bearer in the secret store.
abstract final class PairingCrypto {
  /// Generates a 256-bit random hex token.
  static String newToken() {
    final random = Random.secure();
    return List.generate(
      64,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  /// SHA-256 of [value], hex-encoded.
  static String sha256Hex(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// Constant-time string comparison.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return mismatch == 0;
  }
}
