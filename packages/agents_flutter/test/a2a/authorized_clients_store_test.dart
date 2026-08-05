// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthorizedClientsStore', () {
    late InMemoryKeyValueStore keyValueStore;
    late AuthorizedClientsStore store;

    setUp(() {
      keyValueStore = InMemoryKeyValueStore();
      store = AuthorizedClientsStore(keyValueStore);
    });

    test('add, list, and remove round-trip', () async {
      await store.add(
        clientId: 'client-1',
        clientName: 'Test iPhone',
        bearerHash: 'a' * 64,
      );
      await store.add(
        clientId: 'client-2',
        clientName: 'Test Mac',
        bearerHash: 'b' * 64,
      );

      final listed = await store.list();
      expect(listed, hasLength(2));
      expect(
        listed.map((c) => c.clientName),
        containsAll(['Test iPhone', 'Test Mac']),
      );
      expect(listed.every((c) => c.pairedAt != null), isTrue);

      await store.remove('a' * 64);
      final remaining = await store.list();
      expect(remaining, hasLength(1));
      expect(remaining.single.clientId, 'client-2');
    });

    test('remove revokes the bearer, not just the listing', () async {
      const bearer = 'the-secret-bearer';
      final hash = PairingCrypto.sha256Hex(bearer);
      await store.add(
        clientId: 'client-1',
        clientName: 'Test iPhone',
        bearerHash: hash,
      );
      expect(await store.verify(bearer), isTrue);

      await store.remove(hash);
      expect(await store.verify(bearer), isFalse);
    });

    test('a corrupt record is skipped, not fatal', () async {
      await keyValueStore.write(
        'agents_app.a2a.client.${'c' * 64}',
        'not json at all',
      );
      await store.add(
        clientId: 'client-1',
        clientName: 'Test iPhone',
        bearerHash: 'a' * 64,
      );
      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.clientId, 'client-1');
    });
  });
}
