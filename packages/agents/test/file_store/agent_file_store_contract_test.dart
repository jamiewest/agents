import 'package:agents/src/ai/harness/file_store/agent_file_store.dart';
import 'package:agents/src/ai/harness/file_store/file_store_entry.dart';
import 'package:agents/src/ai/harness/file_store/store_paths.dart';
import 'package:extensions/system.dart';
import 'package:test/test.dart';

void main() {
  group('AgentFileStore.splitLines', () {
    test('keeps each terminator attached', () {
      expect(AgentFileStore.splitLines('a\nb\r\nc\rd'), [
        'a\n',
        'b\r\n',
        'c\r',
        'd',
      ]);
    });

    test('adds no trailing empty line for terminated content', () {
      expect(AgentFileStore.splitLines('a\nb\n'), ['a\n', 'b\n']);
    });
  });

  group('AgentFileStore.scanContent', () {
    test('numbers matches by splitLines and reports them verbatim', () {
      final result = AgentFileStore.scanContent(
        'notes.md',
        'one\r\nmatch\r\nthree',
        RegExp('match', caseSensitive: false),
      );

      expect(result, isNotNull);
      expect(result!.matchingLines, hasLength(1));
      expect(result.matchingLines.single.lineNumber, 2);
      expect(result.matchingLines.single.line, 'match\r\n');
    });

    test('matches an end-anchored pattern past the terminator', () {
      final result = AgentFileStore.scanContent(
        'notes.md',
        'match\r\n',
        RegExp(r'match$'),
      );

      expect(result, isNotNull);
    });

    test('returns null when nothing matches', () {
      final result = AgentFileStore.scanContent(
        'notes.md',
        'nothing here',
        RegExp('match'),
      );

      expect(result, isNull);
    });

    test('anchors the snippet at the match for every terminator', () {
      for (final terminator in ['\n', '\r\n', '\r']) {
        final content = 'a$terminator' * 40 + 'match';
        final result = AgentFileStore.scanContent(
          'notes.md',
          content,
          RegExp('match'),
        );

        final matchIndex = content.indexOf('match');
        expect(
          result!.snippet,
          content.substring(matchIndex - 50, content.length),
          reason: 'terminator ${terminator.codeUnits}',
        );
      }
    });
  });

  group('AgentFileStore default searchFilesAsync', () {
    test(
      'numbers results for a store that implements only the basics',
      () async {
        final store = _MinimalStore({
          'notes.md': 'one\r\nmatch here\r\n',
          'other.md': 'nothing',
        });

        final results = await store.searchFilesAsync('', 'match');

        expect(results, hasLength(1));
        expect(results.single.fileName, 'notes.md');
        expect(results.single.matchingLines.single.lineNumber, 2);
        expect(results.single.matchingLines.single.line, 'match here\r\n');
      },
    );

    test('applies the glob and the non-recursive rule', () async {
      final store = _MinimalStore({
        'notes.md': 'match',
        'notes.txt': 'match',
        'sub/notes.md': 'match',
      });

      final nonRecursive = await store.searchFilesAsync('', 'match', '*.md');
      expect(nonRecursive.map((r) => r.fileName), ['notes.md']);

      final recursive = await store.searchFilesAsync(
        '',
        'match',
        '**/*.md',
        true,
      );
      expect(recursive.map((r) => r.fileName), contains('sub/notes.md'));
    });

    test('re-applies the scope when the hook over-returns', () async {
      final store = _OverReturningStore({
        'notes.md': 'match',
        'sub/notes.md': 'match',
      });

      final results = await store.searchFilesAsync('', 'match');

      // The hook returned the nested file too; the base drops it because the
      // caller did not ask for a recursive search.
      expect(results.map((r) => r.fileName), ['notes.md']);
    });
  });
}

/// A store implementing only the mandatory members, so the base class supplies
/// searching and line numbering.
class _MinimalStore extends AgentFileStore {
  _MinimalStore(this.files);

  final Map<String, String> files;

  @override
  Future<void> writeFileAsync(
    String path,
    String content, [
    CancellationToken? cancellationToken,
  ]) async => files[StorePaths.normalizeRelativePath(path)] = content;

  @override
  Future<String?> readFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async => files[StorePaths.normalizeRelativePath(path)];

  @override
  Future<bool> deleteFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async => files.remove(StorePaths.normalizeRelativePath(path)) != null;

  @override
  Future<List<String>> listFilesAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]) async => [
    for (final entry in await listChildrenAsync(directory, cancellationToken))
      if (entry.type == FileStoreEntry.file) entry.name,
  ];

  @override
  Future<List<FileStoreEntry>> listChildrenAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]) async {
    final prefix = directory.isEmpty ? '' : '$directory/';
    final directories = <String>{};
    final entries = <FileStoreEntry>[];
    for (final name in files.keys) {
      if (!name.startsWith(prefix)) {
        continue;
      }
      final remainder = name.substring(prefix.length);
      final separator = remainder.indexOf('/');
      if (separator < 0) {
        entries.add(FileStoreEntry(remainder, FileStoreEntry.file));
      } else {
        directories.add(remainder.substring(0, separator));
      }
    }
    return [
      for (final name in directories)
        FileStoreEntry(name, FileStoreEntry.directory),
      ...entries,
    ];
  }

  @override
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async => files.containsKey(StorePaths.normalizeRelativePath(path));

  @override
  Future<void> createDirectoryAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {}
}

/// A store whose narrowing hook over-returns, which the contract permits: the
/// base re-applies the caller's scope.
class _OverReturningStore extends _MinimalStore {
  _OverReturningStore(super.files);

  @override
  Future<List<String>> findMatchingFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    bool recursive = false,
    CancellationToken? cancellationToken,
  ]) async => files.keys.toList();
}
