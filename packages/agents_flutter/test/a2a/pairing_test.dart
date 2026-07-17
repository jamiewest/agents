// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:agents_flutter/agents_flutter.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PairingPayload _payload({DateTime? expiresAt}) => PairingPayload(
  hostId: 'host-1',
  host: '192.168.1.10',
  port: 8080,
  token: 'a' * 64,
  expiresAt:
      expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 5)),
);

void main() {
  group('PairingPayload', () {
    test('round-trips through encode/decode', () {
      final original = _payload(expiresAt: DateTime.utc(2026, 7, 1, 12));

      final decoded = PairingPayload.decode(original.encode());

      expect(decoded!.hostId, 'host-1');
      expect(decoded.host, '192.168.1.10');
      expect(decoded.port, 8080);
      expect(decoded.pairingPath, '/pair');
      expect(decoded.token, 'a' * 64);
      expect(decoded.expiresAt, DateTime.utc(2026, 7, 1, 12));
      expect(decoded.baseUrl, 'http://192.168.1.10:8080');
    });

    test('returns null for malformed input and unknown versions', () {
      expect(PairingPayload.decode('not json'), isNull);
      expect(PairingPayload.decode('{"v": 99}'), isNull);
      expect(PairingPayload.decode('{"v": 1}'), isNull);
    });
  });

  group('PairingCrypto', () {
    test('newToken is 256-bit hex and unique', () {
      final token = PairingCrypto.newToken();

      expect(token, hasLength(64));
      expect(token, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(PairingCrypto.newToken(), isNot(token));
    });

    test('sha256Hex matches a known vector', () {
      expect(
        PairingCrypto.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('constantTimeEquals compares correctly', () {
      expect(PairingCrypto.constantTimeEquals('same', 'same'), isTrue);
      expect(PairingCrypto.constantTimeEquals('same', 'sane'), isFalse);
      expect(PairingCrypto.constantTimeEquals('short', 'longer'), isFalse);
      expect(PairingCrypto.constantTimeEquals('', ''), isTrue);
    });
  });

  group('PairingClient.pair', () {
    test('posts the token and parses the host response', () async {
      late http.Request seen;
      final client = PairingClient(
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'credential': 'bearer-1',
              'hostId': 'host-real',
              'deviceName': 'Studio Mac',
            }),
            200,
          );
        }),
      );

      final result = await client.pair(
        _payload(),
        clientName: 'Phone',
        clientId: 'client-9',
      );

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://192.168.1.10:8080/pair');
      final body = (jsonDecode(seen.body) as Map).cast<String, Object?>();
      expect(body, {
        'token': 'a' * 64,
        'clientName': 'Phone',
        'clientId': 'client-9',
      });
      expect(result.credential, 'bearer-1');
      expect(result.hostId, 'host-real');
      expect(result.deviceName, 'Studio Mac');
      expect(result.baseUrl, 'http://192.168.1.10:8080');
    });

    test('rejects an expired payload before any network call', () async {
      var requests = 0;
      final client = PairingClient(
        httpClient: MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        client.pair(
          _payload(
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 1),
            ),
          ),
          clientName: 'Phone',
          clientId: 'c',
        ),
        throwsA(
          isA<PairingException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
      expect(requests, 0);
    });

    test('maps a rejection status to a PairingException', () async {
      final client = PairingClient(
        httpClient: MockClient((request) async => http.Response('nope', 403)),
      );

      await expectLater(
        client.pair(_payload(), clientName: 'Phone', clientId: 'c'),
        throwsA(
          isA<PairingException>().having(
            (e) => e.message,
            'message',
            contains('403'),
          ),
        ),
      );
    });

    test('maps a malformed 200 response to a PairingException', () async {
      for (final body in ['not json', '{"unexpected": true}']) {
        final client = PairingClient(
          httpClient: MockClient((request) async => http.Response(body, 200)),
        );

        await expectLater(
          client.pair(_payload(), clientName: 'Phone', clientId: 'c'),
          throwsA(
            isA<PairingException>().having(
              (e) => e.message,
              'message',
              contains('unexpected'),
            ),
          ),
        );
      }
    });

    test('maps transport failures to a PairingException', () async {
      final client = PairingClient(
        httpClient: MockClient(
          (request) async => throw http.ClientException('refused'),
        ),
      );

      await expectLater(
        client.pair(_payload(), clientName: 'Phone', clientId: 'c'),
        throwsA(
          isA<PairingException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach'),
          ),
        ),
      );
    });

    test('times out instead of hanging on a wedged host', () {
      fakeAsync((async) {
        final client = PairingClient(
          httpClient: MockClient(
            // Never completes; only the timeout can end the call.
            (request) => Completer<http.Response>().future,
          ),
        );

        Object? failure;
        client.pair(_payload(), clientName: 'Phone', clientId: 'c').catchError((
          Object e,
        ) {
          failure = e;
          return const PairingResult(
            credential: '',
            baseUrl: '',
            hostId: '',
            deviceName: '',
          );
        });

        async.elapse(const Duration(seconds: 10));
        expect(failure, isA<PairingException>());
      });
    });
  });

  group('PairingClient.ping', () {
    test('is true only for an authenticated 200', () async {
      final ok = PairingClient(
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer cred');
          return http.Response('{"agents": []}', 200);
        }),
      );
      final unauthorized = PairingClient(
        httpClient: MockClient((request) async => http.Response('no', 401)),
      );
      final unreachable = PairingClient(
        httpClient: MockClient(
          (request) async => throw http.ClientException('down'),
        ),
      );

      expect(await ok.ping('http://h:1', 'cred'), isTrue);
      expect(await unauthorized.ping('http://h:1', 'cred'), isFalse);
      expect(await unreachable.ping('http://h:1', 'cred'), isFalse);
    });
  });

  group('PairingClient.listAgents', () {
    test('parses the agents index', () async {
      final client = PairingClient(
        httpClient: MockClient((request) async {
          expect(request.url.toString(), 'http://h:1/agents');
          expect(request.headers['authorization'], 'Bearer cred');
          return http.Response(
            jsonEncode({
              'agents': [
                {
                  'path': '/agents/researcher',
                  'name': 'Researcher',
                  'description': 'Finds things',
                },
                {'path': '/agents/writer', 'name': 'Writer'},
              ],
            }),
            200,
          );
        }),
      );

      final agents = await client.listAgents('http://h:1', 'cred');

      expect(agents, hasLength(2));
      expect(agents.first.path, '/agents/researcher');
      expect(agents.first.description, 'Finds things');
      expect(agents.last.name, 'Writer');
      expect(agents.last.description, '');
    });

    test('maps failures to PairingException', () async {
      final rejected = PairingClient(
        httpClient: MockClient((request) async => http.Response('no', 500)),
      );
      final malformed = PairingClient(
        httpClient: MockClient(
          (request) async => http.Response('{"agents": "?"}', 200),
        ),
      );

      await expectLater(
        rejected.listAgents('http://h:1', 'cred'),
        throwsA(isA<PairingException>()),
      );
      await expectLater(
        malformed.listAgents('http://h:1', 'cred'),
        throwsA(isA<PairingException>()),
      );
    });
  });
}
