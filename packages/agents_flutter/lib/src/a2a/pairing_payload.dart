// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

/// The pairing offer a host displays as a QR code or copyable text.
///
/// Carries where to reach the host plus a short-lived, single-use [token]
/// that authorizes exactly one `POST /pair` handshake. The token is the
/// only secret: never log it and never place it in model context.
class PairingPayload {
  /// Creates a [PairingPayload].
  const PairingPayload({
    required this.hostId,
    required this.host,
    required this.port,
    required this.token,
    required this.expiresAt,
    this.pairingPath = '/pair',
  });

  /// The wire schema version this class reads and writes.
  static const int schemaVersion = 1;

  /// The host's stable peer id.
  final String hostId;

  /// The host's LAN address (IPv4 or hostname).
  final String host;

  /// The port the host is listening on.
  final int port;

  /// Path of the pairing endpoint on the host.
  final String pairingPath;

  /// Single-use pairing token (256-bit hex).
  final String token;

  /// When the token stops being accepted.
  final DateTime expiresAt;

  /// The host's base URL.
  String get baseUrl => 'http://$host:$port';

  /// Encodes to the compact JSON string placed in the QR code.
  String encode() => jsonEncode({
    'v': schemaVersion,
    'hostId': hostId,
    'host': host,
    'port': port,
    'pairingPath': pairingPath,
    'token': token,
    'exp': expiresAt.toUtc().toIso8601String(),
  });

  /// Decodes a scanned or pasted payload.
  ///
  /// Returns `null` for malformed input or unknown schema versions so
  /// callers can show a friendly error.
  static PairingPayload? decode(String input) {
    try {
      final map = (jsonDecode(input.trim()) as Map).cast<String, Object?>();
      if (map['v'] != schemaVersion) return null;
      return PairingPayload(
        hostId: map['hostId']! as String,
        host: map['host']! as String,
        port: map['port']! as int,
        pairingPath: map['pairingPath'] as String? ?? '/pair',
        token: map['token']! as String,
        expiresAt: DateTime.parse(map['exp']! as String),
      );
    } catch (_) {
      return null;
    }
  }
}
