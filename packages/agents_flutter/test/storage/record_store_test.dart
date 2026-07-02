// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('InMemoryRecordStore', () {
    runRecordStoreContract(() async => InMemoryRecordStore());
  });

  group('SembastRecordStore', () {
    runRecordStoreContract(() async {
      final factory = newDatabaseFactoryMemory();
      return SembastRecordStore(factory.openDatabase('contract-test.db'));
    });
  });
}

/// Runs the [RecordStore] behavioral contract against [createStore].
void runRecordStoreContract(Future<RecordStore> Function() createStore) {
  late RecordStore store;

  setUp(() async {
    store = await createStore();
  });

  Future<void> seedMessages() async {
    await store.put('messages', 'm1', {
      'conversationId': 'c1',
      'seq': 2,
      'text': 'second',
    });
    await store.put('messages', 'm2', {
      'conversationId': 'c1',
      'seq': 1,
      'text': 'first',
    });
    await store.put('messages', 'm3', {
      'conversationId': 'c2',
      'seq': 3,
      'text': 'other conversation',
    });
  }

  test('get returns null for a missing record', () async {
    expect(await store.get('messages', 'missing'), isNull);
  });

  test('put then get round-trips a record', () async {
    final record = {
      'conversationId': 'c1',
      'seq': 1,
      'nested': {'a': true},
    };

    await store.put('messages', 'm1', record);
    final loaded = await store.get('messages', 'm1');

    expect(loaded, record);
  });

  test('put replaces an existing record', () async {
    await store.put('messages', 'm1', {'text': 'before'});

    await store.put('messages', 'm1', {'text': 'after'});
    final loaded = await store.get('messages', 'm1');

    expect(loaded, {'text': 'after'});
  });

  test('collections are isolated by name', () async {
    await store.put('messages', 'shared-id', {'kind': 'message'});
    await store.put('tasks', 'shared-id', {'kind': 'task'});

    expect(await store.get('messages', 'shared-id'), {'kind': 'message'});
    expect(await store.get('tasks', 'shared-id'), {'kind': 'task'});
  });

  test('delete removes a record and tolerates missing ids', () async {
    await store.put('messages', 'm1', {'text': 'hello'});

    await store.delete('messages', 'm1');
    await store.delete('messages', 'm1');

    expect(await store.get('messages', 'm1'), isNull);
  });

  test('query without a query returns every record', () async {
    await seedMessages();

    final results = await store.query('messages');

    expect(results, hasLength(3));
  });

  test('query filters by field equality', () async {
    await seedMessages();

    final results = await store.query(
      'messages',
      query: const RecordQuery(equals: {'conversationId': 'c1'}),
    );

    expect(results.map((r) => r.id).toSet(), {'m1', 'm2'});
  });

  test('query combines multiple equality conditions with AND', () async {
    await seedMessages();

    final results = await store.query(
      'messages',
      query: const RecordQuery(equals: {'conversationId': 'c1', 'seq': 1}),
    );

    expect(results.single.id, 'm2');
  });

  test('query orders ascending and descending', () async {
    await seedMessages();

    final ascending = await store.query(
      'messages',
      query: const RecordQuery(orderBy: 'seq'),
    );
    final descending = await store.query(
      'messages',
      query: const RecordQuery(orderBy: 'seq', descending: true),
    );

    expect(ascending.map((r) => r.value['seq']), [1, 2, 3]);
    expect(descending.map((r) => r.value['seq']), [3, 2, 1]);
  });

  test('query applies offset and limit after ordering', () async {
    await seedMessages();

    final results = await store.query(
      'messages',
      query: const RecordQuery(orderBy: 'seq', offset: 1, limit: 1),
    );

    expect(results.single.value['seq'], 2);
  });

  test('watch emits current results and updates on change', () async {
    await store.put('messages', 'm1', {'conversationId': 'c1', 'seq': 1});

    final emissions = <List<StoredRecord>>[];
    final subscription = store
        .watch(
          'messages',
          query: const RecordQuery(
            equals: {'conversationId': 'c1'},
            orderBy: 'seq',
          ),
        )
        .listen(emissions.add);
    await pumpEventQueue();

    await store.put('messages', 'm2', {'conversationId': 'c1', 'seq': 2});
    await pumpEventQueue();
    await subscription.cancel();

    expect(emissions.first, hasLength(1));
    expect(emissions.last, hasLength(2));
    expect(emissions.last.map((r) => r.value['seq']), [1, 2]);
  });

  test('deleteWhere removes only matching records', () async {
    await seedMessages();

    await store.deleteWhere(
      'messages',
      const RecordQuery(equals: {'conversationId': 'c1'}),
    );
    final remaining = await store.query('messages');

    expect(remaining.single.id, 'm3');
  });

  test('returned records are defensive copies', () async {
    await store.put('messages', 'm1', {'text': 'original'});

    final loaded = await store.get('messages', 'm1');
    loaded!['text'] = 'mutated';

    expect((await store.get('messages', 'm1'))!['text'], 'original');
  });
}
