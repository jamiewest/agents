import 'package:agents/src/ai/harness/file_store/in_memory_agent_file_store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryAgentFileStore', () {
    test('write and read file returns content', () async {
      final store = InMemoryAgentFileStore();

      await store.writeFileAsync('notes.md', 'Hello world');
      final content = await store.readFileAsync('notes.md');

      expect(content, 'Hello world');
    });

    test('read file non-existent returns null', () async {
      final store = InMemoryAgentFileStore();

      final content = await store.readFileAsync('nonexistent.md');

      expect(content, isNull);
    });

    test('write file overwrites existing', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Original');

      await store.writeFileAsync('notes.md', 'Updated');
      final content = await store.readFileAsync('notes.md');

      expect(content, 'Updated');
    });

    test('delete file existing file returns true', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');

      final deleted = await store.deleteFileAsync('notes.md');

      expect(deleted, isTrue);
      expect(await store.readFileAsync('notes.md'), isNull);
    });

    test('delete file non-existent returns false', () async {
      final store = InMemoryAgentFileStore();

      final deleted = await store.deleteFileAsync('nonexistent.md');

      expect(deleted, isFalse);
    });

    test('list files returns direct children', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/file1.md', 'Content 1');
      await store.writeFileAsync('folder/file2.md', 'Content 2');
      await store.writeFileAsync('folder/sub/file3.md', 'Content 3');
      await store.writeFileAsync('other/file4.md', 'Content 4');

      final files = await store.listFilesAsync('folder');

      expect(files, unorderedEquals(['file1.md', 'file2.md']));
    });

    test('list files empty directory returns empty', () async {
      final store = InMemoryAgentFileStore();

      final files = await store.listFilesAsync('empty');

      expect(files, isEmpty);
    });

    test('list files root directory returns root files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('root.md', 'Content');
      await store.writeFileAsync('folder/nested.md', 'Content');

      final files = await store.listFilesAsync('');

      expect(files, ['root.md']);
    });

    test('list files includes description files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'Content');
      await store.writeFileAsync('folder/notes_description.md', 'Desc');

      final files = await store.listFilesAsync('folder');

      expect(files, unorderedEquals(['notes.md', 'notes_description.md']));
    });

    test('file exists returns true only for existing files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('notes.md', 'Content');

      expect(await store.fileExistsAsync('notes.md'), isTrue);
      expect(await store.fileExistsAsync('nonexistent.md'), isFalse);
    });

    test('file paths are case-insensitive', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('Folder/Notes.md', 'Content');

      expect(await store.readFileAsync('folder/notes.md'), 'Content');
      expect(await store.fileExistsAsync('FOLDER/NOTES.MD'), isTrue);
    });

    test('search files finds matching content', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync(
        'folder/notes.md',
        'The quick brown fox jumps over the lazy dog',
      );
      await store.writeFileAsync('folder/other.md', 'No match here');

      final results = await store.searchFilesAsync('folder', 'brown fox');

      expect(results, hasLength(1));
      expect(results[0].fileName, 'notes.md');
      expect(results[0].snippet, contains('brown fox'));
    });

    test('search files returns matching line numbers', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync(
        'folder/notes.md',
        'Line one\nLine two with match\nLine three\nLine four with match',
      );

      final results = await store.searchFilesAsync('folder', 'match');

      expect(results, hasLength(1));
      expect(results[0].matchingLines, hasLength(2));
      expect(results[0].matchingLines[0].lineNumber, 2);
      expect(results[0].matchingLines[0].line, 'Line two with match');
      expect(results[0].matchingLines[1].lineNumber, 4);
      expect(results[0].matchingLines[1].line, 'Line four with match');
    });

    test('search files strips trailing carriage return from line', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'first\r\nmatch here\r\n');

      final results = await store.searchFilesAsync('folder', 'match');

      expect(results[0].matchingLines[0].line, 'match here');
    });

    test('search files is case-insensitive', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'Important Data Here');

      final results = await store.searchFilesAsync('folder', 'important data');

      expect(results, hasLength(1));
    });

    test('search files supports regex pattern', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync(
        'folder/notes.md',
        'Error: something went wrong\nWarning: check this\nInfo: all good',
      );

      final results = await store.searchFilesAsync('folder', 'error|warning');

      expect(results, hasLength(1));
      expect(results[0].matchingLines, hasLength(2));
      expect(results[0].matchingLines[0].lineNumber, 1);
      expect(results[0].matchingLines[1].lineNumber, 2);
    });

    test('search files supports regex with special characters', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync(
        'folder/code.cs',
        'var x = 42;\nvar y = 100;\nconst z = 7;',
      );

      final results = await store.searchFilesAsync('folder', r'^var\b');

      expect(results, hasLength(1));
      expect(results[0].matchingLines, hasLength(2));
    });

    test('search files with glob pattern filters files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'Important data');
      await store.writeFileAsync('folder/data.txt', 'Important data');
      await store.writeFileAsync('folder/code.cs', 'Important data');

      final results = await store.searchFilesAsync(
        'folder',
        'Important',
        '*.md',
      );

      expect(results, hasLength(1));
      expect(results[0].fileName, 'notes.md');
    });

    test('search files with glob pattern supports prefix match', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/research_ai.md', 'findings');
      await store.writeFileAsync('folder/research_ml.md', 'findings');
      await store.writeFileAsync('folder/notes.md', 'findings');

      final results = await store.searchFilesAsync(
        'folder',
        'findings',
        'research*',
      );

      expect(results, hasLength(2));
      expect(results.every((r) => r.fileName.startsWith('research')), isTrue);
    });

    test('search files with null glob pattern searches all files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'match');
      await store.writeFileAsync('folder/data.txt', 'match');

      final results = await store.searchFilesAsync('folder', 'match', null);

      expect(results, hasLength(2));
    });

    test('search files no match returns empty', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'Some content');

      final results = await store.searchFilesAsync(
        'folder',
        'nonexistent query',
      );

      expect(results, isEmpty);
    });

    test('search files ignores subdirectory files', () async {
      final store = InMemoryAgentFileStore();
      await store.writeFileAsync('folder/notes.md', 'Match here');
      await store.writeFileAsync('folder/sub/deep.md', 'Match here too');

      final results = await store.searchFilesAsync('folder', 'Match');

      expect(results, hasLength(1));
      expect(results[0].fileName, 'notes.md');
    });

    test('search files snippet includes surrounding context', () async {
      final store = InMemoryAgentFileStore();
      final padding = 'A' * 60;
      final content = '${padding}MATCH_HERE$padding';
      await store.writeFileAsync('folder/file.md', content);

      final results = await store.searchFilesAsync('folder', 'MATCH_HERE');

      expect(results, hasLength(1));
      final snippet = results[0].snippet;
      expect(snippet, contains('MATCH_HERE'));
      expect(snippet.length, lessThanOrEqualTo(50 + 'MATCH_HERE'.length + 50));
      expect(snippet.length, greaterThan('MATCH_HERE'.length));
    });

    test('search files snippet match near start of file', () async {
      final store = InMemoryAgentFileStore();
      final content = 'MATCH${'B' * 80}';
      await store.writeFileAsync('folder/file.md', content);

      final results = await store.searchFilesAsync('folder', 'MATCH');

      expect(results, hasLength(1));
      expect(results[0].snippet, startsWith('MATCH'));
      expect(results[0].snippet.length, lessThanOrEqualTo('MATCH'.length + 50));
    });

    test('search files snippet match near end of file', () async {
      final store = InMemoryAgentFileStore();
      final content = '${'C' * 80}MATCH';
      await store.writeFileAsync('folder/file.md', content);

      final results = await store.searchFilesAsync('folder', 'MATCH');

      expect(results, hasLength(1));
      expect(results[0].snippet, endsWith('MATCH'));
      expect(results[0].snippet.length, lessThanOrEqualTo(50 + 'MATCH'.length));
    });

    test('search files snippet uses first match position', () async {
      final store = InMemoryAgentFileStore();
      const content =
          'Line one has some text\nLine two is filler\nLine three has UNIQUE_MARKER here';
      await store.writeFileAsync('folder/file.md', content);

      final results = await store.searchFilesAsync('folder', 'UNIQUE_MARKER');

      expect(results, hasLength(1));
      expect(results[0].snippet, contains('UNIQUE_MARKER'));
      expect(results[0].snippet, contains('Line three'));
    });

    test('search files snippet correct for multi-line match', () async {
      final store = InMemoryAgentFileStore();
      final line1 = 'X' * 100;
      final line2 = '${'Y' * 60}FIND_ME${'Z' * 60}';
      final line3 = 'W' * 100;
      final content = '$line1\n$line2\n$line3';
      await store.writeFileAsync('folder/file.md', content);

      final results = await store.searchFilesAsync('folder', 'FIND_ME');

      expect(results, hasLength(1));
      expect(results[0].snippet, contains('FIND_ME'));
      expect(results[0].snippet, isNot(contains('XXXX')));
    });

    test(
      'path normalization handles backslashes and trailing slashes',
      () async {
        final store = InMemoryAgentFileStore();

        await store.writeFileAsync(r'folder\file.md/', 'Content');
        final content = await store.readFileAsync('folder/file.md');

        expect(content, 'Content');
      },
    );

    test('write file path traversal throws', () async {
      final store = InMemoryAgentFileStore();

      await expectLater(
        store.writeFileAsync('../escape.md', 'Content'),
        throwsArgumentError,
      );
    });

    test('read file path traversal throws', () async {
      final store = InMemoryAgentFileStore();

      await expectLater(
        store.readFileAsync('folder/../../escape.md'),
        throwsArgumentError,
      );
    });

    test('write file absolute path throws', () async {
      final store = InMemoryAgentFileStore();

      await expectLater(
        store.writeFileAsync('/etc/passwd', 'Content'),
        throwsArgumentError,
      );
    });

    test('write file double dots in file name allowed', () async {
      final store = InMemoryAgentFileStore();

      await store.writeFileAsync('notes..md', 'Content');
      final content = await store.readFileAsync('notes..md');

      expect(content, 'Content');
    });

    test('write file drive-rooted path throws', () async {
      final store = InMemoryAgentFileStore();

      await expectLater(
        store.writeFileAsync(r'C:\temp\file.md', 'Content'),
        throwsArgumentError,
      );
    });

    test('list files path traversal throws', () async {
      final store = InMemoryAgentFileStore();

      await expectLater(store.listFilesAsync('../other'), throwsArgumentError);
    });

    test('create directory is no-op but validates paths', () async {
      final store = InMemoryAgentFileStore();

      await store.createDirectoryAsync('folder');
      await expectLater(
        store.createDirectoryAsync('../folder'),
        throwsArgumentError,
      );
    });
  });
}
