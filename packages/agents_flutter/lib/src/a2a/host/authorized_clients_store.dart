// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import '../../configured_agents/storage/key_value_store.dart';
import '../pairing_crypto.dart';

/// A paired client as recorded at pairing time.
class PairedClient {
  /// Creates a [PairedClient].
  const PairedClient({
    required this.bearerHash,
    required this.clientId,
    required this.clientName,
    this.pairedAt,
  });

  /// SHA-256 of the client's bearer — the storage key, and the handle
  /// [AuthorizedClientsStore.remove] takes. The bearer itself is never
  /// stored.
  final String bearerHash;

  /// The id the client presented when pairing.
  final String clientId;

  /// The name the client presented when pairing.
  final String clientName;

  /// When the pairing happened, if the record carries it.
  final DateTime? pairedAt;
}

/// Paired clients, persisted as SHA-256 hashes of their bearers.
///
/// Platform-neutral on purpose: the host server exists only where `dart:io`
/// does, but listing and revoking pairings is plain key-value work any
/// platform can do.
class AuthorizedClientsStore {
  /// Creates an [AuthorizedClientsStore] over [keyValueStore].
  AuthorizedClientsStore(this._keyValueStore);

  static const String _prefix = 'agents_app.a2a.client.';

  final KeyValueStore _keyValueStore;

  /// Records a paired client. Only the bearer's hash is stored.
  Future<void> add({
    required String clientId,
    required String clientName,
    required String bearerHash,
  }) => _keyValueStore.write(
    '$_prefix$bearerHash',
    jsonEncode({
      'clientId': clientId,
      'clientName': clientName,
      'pairedAt': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  /// Whether [bearer] belongs to a paired client.
  Future<bool> verify(String bearer) async {
    final hash = PairingCrypto.sha256Hex(bearer);
    for (final key in await _keyValueStore.keys(prefix: _prefix)) {
      if (PairingCrypto.constantTimeEquals(
        key.substring(_prefix.length),
        hash,
      )) {
        return true;
      }
    }
    return false;
  }

  /// All paired clients, newest first.
  ///
  /// Records that fail to parse are skipped rather than failing the whole
  /// listing — one corrupt entry must not make every pairing invisible
  /// (and thus unrevokable).
  Future<List<PairedClient>> list() async {
    final clients = <PairedClient>[];
    for (final key in await _keyValueStore.keys(prefix: _prefix)) {
      final raw = await _keyValueStore.read(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        clients.add(
          PairedClient(
            bearerHash: key.substring(_prefix.length),
            clientId: json['clientId'] as String? ?? '',
            clientName: json['clientName'] as String? ?? 'Unknown device',
            pairedAt: DateTime.tryParse(json['pairedAt'] as String? ?? ''),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    clients.sort((a, b) {
      final at = a.pairedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.pairedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return clients;
  }

  /// Forgets the client stored under [bearerHash].
  ///
  /// Verification re-reads the store on every request, so the peer's very
  /// next call fails with 401 — no server restart needed. The peer keeps
  /// its saved teammate config and simply starts getting refusals, which
  /// is the correct shape for revocation.
  Future<void> remove(String bearerHash) =>
      _keyValueStore.delete('$_prefix$bearerHash');
}
