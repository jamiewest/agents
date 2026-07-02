// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pairing_payload.dart';

/// The result of a successful pairing handshake.
class PairingResult {
  /// Creates a [PairingResult].
  const PairingResult({
    required this.credential,
    required this.baseUrl,
    required this.hostId,
    required this.deviceName,
  });

  /// The long-lived bearer credential for authenticated requests.
  ///
  /// Store it in the secret store; never log it.
  final String credential;

  /// The host's base URL.
  final String baseUrl;

  /// The host's stable peer id.
  final String hostId;

  /// The host's human-readable name.
  final String deviceName;
}

/// One agent offered by a paired host.
class HostedAgentSummary {
  /// Creates a [HostedAgentSummary].
  const HostedAgentSummary({
    required this.path,
    required this.name,
    this.description = '',
  });

  /// The agent's path on the host (e.g. `/agents/researcher`).
  final String path;

  /// The agent's display name.
  final String name;

  /// What the agent does.
  final String description;
}

/// Thrown when pairing or discovery fails.
class PairingException implements Exception {
  /// Creates a [PairingException].
  PairingException(this.message);

  /// What went wrong, phrased for direct display.
  final String message;

  @override
  String toString() => message;
}

/// Client side of the pairing handshake and agent discovery.
class PairingClient {
  /// Creates a [PairingClient].
  PairingClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Redeems [payload]'s single-use token for a long-lived credential.
  Future<PairingResult> pair(
    PairingPayload payload, {
    required String clientName,
    required String clientId,
  }) async {
    if (DateTime.now().toUtc().isAfter(payload.expiresAt)) {
      throw PairingException(
        'This pairing code has expired. Generate a new one on the host.',
      );
    }

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('${payload.baseUrl}${payload.pairingPath}'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'token': payload.token,
          'clientName': clientName,
          'clientId': clientId,
        }),
      );
    } catch (e) {
      throw PairingException(
        'Could not reach ${payload.baseUrl}. Make sure both devices are on '
        'the same network. ($e)',
      );
    }
    if (response.statusCode != 200) {
      throw PairingException(
        'The host rejected the pairing code (HTTP ${response.statusCode}). '
        'Codes are single-use and expire quickly — generate a new one.',
      );
    }

    final map = (jsonDecode(response.body) as Map).cast<String, Object?>();
    return PairingResult(
      credential: map['credential']! as String,
      baseUrl: map['baseUrl'] as String? ?? payload.baseUrl,
      hostId: map['hostId'] as String? ?? payload.hostId,
      deviceName: map['deviceName'] as String? ?? payload.host,
    );
  }

  /// Whether a paired host is currently reachable with [credential].
  ///
  /// A cheap authenticated probe of the agents index; used for health
  /// checks before running a remote agent.
  Future<bool> ping(String baseUrl, String credential) async {
    try {
      final response = await _http
          .get(
            Uri.parse('$baseUrl/agents'),
            headers: {'authorization': 'Bearer $credential'},
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Lists the agents a paired host offers.
  Future<List<HostedAgentSummary>> listAgents(
    String baseUrl,
    String credential,
  ) async {
    final response = await _http.get(
      Uri.parse('$baseUrl/agents'),
      headers: {'authorization': 'Bearer $credential'},
    );
    if (response.statusCode != 200) {
      throw PairingException(
        'Could not list the host\'s agents (HTTP ${response.statusCode}).',
      );
    }
    final list = (jsonDecode(response.body) as Map)['agents']! as List;
    return [
      for (final entry in list.cast<Map>())
        HostedAgentSummary(
          path: entry['path']! as String,
          name: entry['name']! as String,
          description: entry['description'] as String? ?? '',
        ),
    ];
  }
}
