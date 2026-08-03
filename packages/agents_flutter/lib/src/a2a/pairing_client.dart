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
  ///
  /// When [httpClient] is omitted the client creates and owns one; call
  /// [close] to release its connections. An injected client stays owned by
  /// the caller and is left open.
  PairingClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  /// How long [pair] and [listAgents] wait before giving up on the host.
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// Timeout for a single request to [baseUrl].
  ///
  /// An onion address needs far longer than a LAN hop. The first connection
  /// has to fetch the service descriptor from the directory system and build
  /// a rendezvous circuit, which routinely takes tens of seconds; a freshly
  /// published service is slower still while its descriptor propagates.
  /// Timing that out at LAN speed reports a working setup as unreachable.
  static Duration _timeoutFor(String baseUrl) =>
      _isOnion(baseUrl) ? const Duration(seconds: 90) : _requestTimeout;

  static bool _isOnion(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    return host.endsWith('.onion');
  }

  /// Explains an unreachable host in terms of the route actually used.
  ///
  /// "Check you are on the same network" is not merely unhelpful for an onion
  /// address, it points away from the fix: Tor exists so the devices do not
  /// have to share a network.
  static String _unreachable(String baseUrl, Object error) => _isOnion(baseUrl)
      ? 'Could not reach $baseUrl over Tor. Check that Tor is on and '
            'connected on both devices, and that the other device is still '
            'sharing. A first connection can take up to a minute. ($error)'
      : 'Could not reach $baseUrl. Make sure both devices are on '
            'the same network. ($error)';

  final http.Client _http;
  final bool _ownsHttp;

  /// Releases the HTTP client when this instance created it.
  void close() {
    if (_ownsHttp) {
      _http.close();
    }
  }

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
      response = await _http
          .post(
            Uri.parse('${payload.baseUrl}${payload.pairingPath}'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'token': payload.token,
              'clientName': clientName,
              'clientId': clientId,
            }),
          )
          .timeout(_timeoutFor(payload.baseUrl));
    } catch (e) {
      throw PairingException(_unreachable(payload.baseUrl, e));
    }
    if (response.statusCode != 200) {
      throw PairingException(
        'The host rejected the pairing code (HTTP ${response.statusCode}). '
        'Codes are single-use and expire quickly — generate a new one.',
      );
    }

    try {
      final map = (jsonDecode(response.body) as Map).cast<String, Object?>();
      return PairingResult(
        credential: map['credential']! as String,
        baseUrl: map['baseUrl'] as String? ?? payload.baseUrl,
        hostId: map['hostId'] as String? ?? payload.hostId,
        deviceName: map['deviceName'] as String? ?? payload.host,
      );
    } catch (e) {
      throw PairingException(
        'The host sent an unexpected pairing response. ($e)',
      );
    }
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
          .timeout(_timeoutFor(baseUrl));
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
    final http.Response response;
    try {
      response = await _http
          .get(
            Uri.parse('$baseUrl/agents'),
            headers: {'authorization': 'Bearer $credential'},
          )
          .timeout(_timeoutFor(baseUrl));
    } catch (e) {
      throw PairingException(_unreachable(baseUrl, e));
    }
    if (response.statusCode != 200) {
      throw PairingException(
        'Could not list the host\'s agents (HTTP ${response.statusCode}).',
      );
    }
    try {
      final list = (jsonDecode(response.body) as Map)['agents']! as List;
      return [
        for (final entry in list.cast<Map>())
          HostedAgentSummary(
            path: entry['path']! as String,
            name: entry['name']! as String,
            description: entry['description'] as String? ?? '',
          ),
      ];
    } catch (e) {
      throw PairingException(
        'The host sent an unexpected agents response. ($e)',
      );
    }
  }
}
