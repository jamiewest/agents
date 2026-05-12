import 'package:agents/src/ai/harness/file_store/store_paths.dart';
import 'package:test/test.dart';

void main() {
  group('StorePaths', () {
    group('normalizeRelativePath - valid paths', () {
      test('valid path returns normalized', () {
        expect(StorePaths.normalizeRelativePath('file.md'), 'file.md');
        expect(
          StorePaths.normalizeRelativePath('folder/file.md'),
          'folder/file.md',
        );
        expect(StorePaths.normalizeRelativePath('a/b/c.txt'), 'a/b/c.txt');
      });

      test('backslashes normalize to forward slash', () {
        expect(
          StorePaths.normalizeRelativePath(r'folder\file.md'),
          'folder/file.md',
        );
        expect(StorePaths.normalizeRelativePath(r'a\b\c.txt'), 'a/b/c.txt');
      });

      test('consecutive separators are collapsed', () {
        expect(
          StorePaths.normalizeRelativePath('folder//file.md'),
          'folder/file.md',
        );
        expect(StorePaths.normalizeRelativePath('a///b////c.txt'), 'a/b/c.txt');
      });

      test('trailing slash is trimmed', () {
        expect(StorePaths.normalizeRelativePath('file.md/'), 'file.md');
      });

      test('leading slash throws', () {
        expect(
          () => StorePaths.normalizeRelativePath('/file.md'),
          throwsArgumentError,
        );
        expect(
          () => StorePaths.normalizeRelativePath('/folder/file.md/'),
          throwsArgumentError,
        );
      });
    });

    group('normalizeRelativePath - rejected paths', () {
      test('traversal segments throw', () {
        for (final input in [
          '../file.md',
          'folder/../file.md',
          './file.md',
          'folder/./file.md',
        ]) {
          expect(
            () => StorePaths.normalizeRelativePath(input),
            throwsArgumentError,
          );
        }
      });

      test('drive roots throw', () {
        for (final input in [r'C:\file.md', 'C:/file.md', 'D:file.md']) {
          expect(
            () => StorePaths.normalizeRelativePath(input),
            throwsArgumentError,
          );
        }
      });

      test('empty file throws', () {
        expect(() => StorePaths.normalizeRelativePath(''), throwsArgumentError);
      });

      test('whitespace-only file throws', () {
        expect(
          () => StorePaths.normalizeRelativePath('   '),
          throwsArgumentError,
        );
      });
    });

    group('normalizeRelativePath - directory mode', () {
      test('empty directory returns empty', () {
        expect(StorePaths.normalizeRelativePath('', isDirectory: true), '');
      });

      test('directory mode normalizes path', () {
        expect(
          StorePaths.normalizeRelativePath('folder', isDirectory: true),
          'folder',
        );
        expect(
          StorePaths.normalizeRelativePath('a/b', isDirectory: true),
          'a/b',
        );
        expect(
          StorePaths.normalizeRelativePath(r'a\b/', isDirectory: true),
          'a/b',
        );
      });

      test('directory traversal throws', () {
        expect(
          () =>
              StorePaths.normalizeRelativePath('../folder', isDirectory: true),
          throwsArgumentError,
        );
      });
    });

    group('glob matching', () {
      test('with matcher matches correctly', () {
        final cases = [
          ('*.md', 'notes.md', true),
          ('*.md', 'notes.txt', false),
          ('research*', 'research_results.md', true),
          ('research*', 'notes.md', false),
          ('*.md', 'NOTES.MD', true),
          ('file?.txt', 'file1.txt', true),
          ('file?.txt', 'file10.txt', false),
        ];

        for (final (pattern, fileName, expected) in cases) {
          final matcher = StorePaths.createGlobMatcher(pattern);
          expect(StorePaths.matchesGlob(fileName, matcher), expected);
        }
      });

      test('null matcher returns true', () {
        expect(StorePaths.matchesGlob('anything.txt', null), isTrue);
      });
    });
  });
}
