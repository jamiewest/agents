import 'dart:io';

import 'package:agents/src/ai/harness/file_store/file_system_agent_file_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FileSystemAgentFileStore', () {
    late Directory rootDir;
    late FileSystemAgentFileStore store;

    setUp(() {
      rootDir = Directory.systemTemp.createTempSync(
        'FileSystemAgentFileStoreTests_',
      );
      rootDir.deleteSync(recursive: true);
      store = FileSystemAgentFileStore(rootDir.path);
    });

    tearDown(() {
      if (rootDir.existsSync()) {
        rootDir.deleteSync(recursive: true);
      }
    });

    group('constructor', () {
      test('creates root directory', () {
        expect(rootDir.existsSync(), isTrue);
      });

      test('null root directory throws', () {
        expect(() => FileSystemAgentFileStore(null), throwsArgumentError);
      });

      test('empty root directory throws', () {
        expect(() => FileSystemAgentFileStore(''), throwsArgumentError);
      });

      test('whitespace root directory throws', () {
        expect(() => FileSystemAgentFileStore('   '), throwsArgumentError);
      });
    });

    group('path traversal rejection', () {
      test('write file dot dot segment throws', () async {
        await expectLater(
          store.writeFileAsync('../escape.txt', 'content'),
          throwsArgumentError,
        );
      });

      test('read file absolute path throws', () async {
        await expectLater(
          store.readFileAsync('/etc/passwd'),
          throwsArgumentError,
        );
      });

      test('delete file drive-rooted path throws', () async {
        await expectLater(
          store.deleteFileAsync(r'C:\temp\file.txt'),
          throwsArgumentError,
        );
      });

      test('write file dot segment throws', () async {
        await expectLater(
          store.writeFileAsync('./file.txt', 'content'),
          throwsArgumentError,
        );
      });

      test('write file double dots in file name allowed', () async {
        await store.writeFileAsync('notes..md', 'content');

        final result = await store.readFileAsync('notes..md');

        expect(result, 'content');
      });

      test('write file trailing slash normalizes', () async {
        await store.writeFileAsync('subdir/', 'content');

        final result = await store.readFileAsync('subdir');

        expect(result, 'content');
      });
    });

    group('write and read', () {
      test('round trips', () async {
        await store.writeFileAsync('test.txt', 'hello world');

        final content = await store.readFileAsync('test.txt');

        expect(content, 'hello world');
      });

      test('overwrites existing', () async {
        await store.writeFileAsync('test.txt', 'first');
        await store.writeFileAsync('test.txt', 'second');

        final content = await store.readFileAsync('test.txt');

        expect(content, 'second');
      });

      test('read non-existent returns null', () async {
        final content = await store.readFileAsync('missing.txt');

        expect(content, isNull);
      });
    });

    group('delete', () {
      test('existing file returns true', () async {
        await store.writeFileAsync('delete-me.txt', 'content');

        final deleted = await store.deleteFileAsync('delete-me.txt');

        expect(deleted, isTrue);
        expect(await store.readFileAsync('delete-me.txt'), isNull);
      });

      test('non-existent returns false', () async {
        final deleted = await store.deleteFileAsync('nope.txt');

        expect(deleted, isFalse);
      });
    });

    group('file exists', () {
      test('existing file returns true', () async {
        await store.writeFileAsync('exists.txt', 'content');

        expect(await store.fileExistsAsync('exists.txt'), isTrue);
      });

      test('non-existent returns false', () async {
        expect(await store.fileExistsAsync('missing.txt'), isFalse);
      });
    });

    group('list files', () {
      test('returns direct children only', () async {
        await store.writeFileAsync('root.txt', 'content');
        await store.writeFileAsync('sub/nested.txt', 'content');

        final files = await store.listFilesAsync('');

        expect(files, ['root.txt']);
      });

      test('subdirectory returns children', () async {
        await store.writeFileAsync('sub/a.txt', 'content');
        await store.writeFileAsync('sub/b.txt', 'content');
        await store.writeFileAsync('other.txt', 'content');

        final files = await store.listFilesAsync('sub');

        expect(files, unorderedEquals(['a.txt', 'b.txt']));
      });

      test('non-existent directory returns empty', () async {
        final files = await store.listFilesAsync('no-such-dir');

        expect(files, isEmpty);
      });
    });

    group('create directory', () {
      test('creates on disk', () async {
        await store.createDirectoryAsync('new-dir');

        expect(Directory(p.join(rootDir.path, 'new-dir')).existsSync(), isTrue);
      });
    });

    group('search files', () {
      test('finds match', () async {
        await store.writeFileAsync(
          'doc.md',
          'This has an error on line one.\nLine two is fine.',
        );

        final results = await store.searchFilesAsync('', 'error');

        expect(results, hasLength(1));
        expect(results[0].fileName, 'doc.md');
        expect(results[0].matchingLines, hasLength(1));
        expect(results[0].matchingLines[0].lineNumber, 1);
        expect(results[0].snippet, contains('error'));
      });

      test('glob filter excludes non-matching', () async {
        await store.writeFileAsync('notes.md', 'important info');
        await store.writeFileAsync('data.txt', 'important info');

        final results = await store.searchFilesAsync('', 'important', '*.md');

        expect(results, hasLength(1));
        expect(results[0].fileName, 'notes.md');
      });

      test('searches direct files only', () async {
        await store.writeFileAsync('notes.md', 'match here');
        await store.writeFileAsync('sub/deep.md', 'match here too');

        final results = await store.searchFilesAsync('', 'match');

        expect(results, hasLength(1));
        expect(results[0].fileName, 'notes.md');
      });

      test('no match returns empty', () async {
        await store.writeFileAsync('doc.md', 'nothing here');

        final results = await store.searchFilesAsync('', 'missing-pattern');

        expect(results, isEmpty);
      });

      test('non-existent directory returns empty', () async {
        final results = await store.searchFilesAsync('no-dir', 'anything');

        expect(results, isEmpty);
      });
    });
  });
}
