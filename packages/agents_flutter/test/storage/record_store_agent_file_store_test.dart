// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents_flutter/agents_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryRecordStore records;

  setUp(() => records = InMemoryRecordStore());

  RecordStoreAgentFileStore store({String namespace = 'conv-1'}) =>
      RecordStoreAgentFileStore(records, namespace: namespace);

  group('RecordStoreAgentFileStore', () {
    test('writes, reads, overwrites, and deletes files', () async {
      final target = store();

      await target.writeFileAsync('notes/todo.md', 'first');
      expect(await target.readFileAsync('notes/todo.md'), 'first');
      expect(await target.fileExistsAsync('notes/todo.md'), isTrue);

      await target.writeFileAsync('notes/todo.md', 'second');
      expect(await target.readFileAsync('notes/todo.md'), 'second');

      expect(await target.deleteFileAsync('notes/todo.md'), isTrue);
      expect(await target.deleteFileAsync('notes/todo.md'), isFalse);
      expect(await target.readFileAsync('notes/todo.md'), isNull);
    });

    test('persists across store instances over the same records', () async {
      await store().writeFileAsync('kept.txt', 'still here');

      expect(await store().readFileAsync('kept.txt'), 'still here');
    });

    test('namespaces are isolated', () async {
      await store(namespace: 'conv-1').writeFileAsync('shared.txt', 'mine');

      final other = store(namespace: 'conv-2');
      expect(await other.readFileAsync('shared.txt'), isNull);
      expect(await other.listFilesAsync(''), isEmpty);
    });

    test('lists only direct children of a directory', () async {
      final target = store();
      await target.writeFileAsync('a.txt', '1');
      await target.writeFileAsync('docs/b.txt', '2');
      await target.writeFileAsync('docs/deep/c.txt', '3');

      expect(await target.listFilesAsync(''), ['a.txt']);
      expect(await target.listFilesAsync('docs'), ['b.txt']);
    });

    test('searches content by regex with an optional glob', () async {
      final target = store();
      await target.writeFileAsync('log.txt', 'ok\nERROR: broke\nok');
      await target.writeFileAsync('data.csv', 'error,1');

      final results = await target.searchFilesAsync('', 'error', '*.txt');

      expect(results, hasLength(1));
      expect(results.single.fileName, 'log.txt');
      expect(results.single.matchingLines.single.lineNumber, 2);
      expect(results.single.snippet, contains('ERROR'));
    });

    test('rejects traversal paths', () async {
      expect(
        () => store().writeFileAsync('../escape.txt', 'x'),
        throwsArgumentError,
      );
    });
  });
}
