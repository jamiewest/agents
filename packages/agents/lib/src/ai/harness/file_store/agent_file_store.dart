import 'dart:math';

import 'package:extensions/system.dart';

import 'file_editor.dart';
import 'file_search_match.dart';
import 'file_search_result.dart';
import 'file_store_entry.dart';
import 'store_paths.dart';

/// Provides an abstract base class for file storage operations.
///
/// All paths are relative to an implementation-defined root. Implementations
/// may map these paths to a local file system, in-memory store, remote blob
/// storage, or other mechanisms. Paths use forward slashes as separators and
/// must not escape the root (e.g., via `..` segments). It is up to each
/// implementation to enforce this.
abstract class AgentFileStore {
  AgentFileStore();

  /// Writes content to a file, creating or overwriting it.
  Future<void> writeFileAsync(
    String path,
    String content, [
    CancellationToken? cancellationToken,
  ]);

  /// Reads the content of a file.
  Future<String?> readFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Deletes a file.
  Future<bool> deleteFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Lists files in a directory.
  Future<List<String>> listFilesAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]);

  /// Lists the direct children (files and subdirectories) of a directory.
  ///
  /// Use an empty string for the root. Subdirectories are listed before
  /// files.
  Future<List<FileStoreEntry>> listChildrenAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]);

  /// Checks whether a file exists.
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);

  /// Searches for files whose content matches a regular expression pattern.
  ///
  /// When [recursive] is `true`, files in subdirectories of [directory] are
  /// searched as well; result file names are paths relative to [directory]
  /// (using forward slashes). [filePattern] is a glob matched against each
  /// file's relative path.
  ///
  /// Implementers overriding this method must report
  /// [FileSearchMatch.lineNumber] as a 1-based coordinate into [splitLines]
  /// of the same content [readFileAsync] returns, and should report
  /// [FileSearchMatch.line] verbatim, terminator included. [scanContent]
  /// produces both correctly and is the recommended way to build results.
  ///
  /// Numbering against anything else — a different split rule, or content
  /// this store does not serve through [readFileAsync] — is a bug with a
  /// silent failure mode: the search looks correct, and the damage appears
  /// later when a line edit applies to a line the caller never saw. Cover it
  /// with a test that greps and then edits by the reported number.
  Future<List<FileSearchResult>> searchFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    bool recursive = false,
    CancellationToken? cancellationToken,
  ]) async {
    final regex = RegExp(regexPattern, caseSensitive: false);
    final names = await findMatchingFilesAsync(
      directory,
      regexPattern,
      filePattern,
      recursive,
      cancellationToken,
    );
    final matcher = filePattern != null
        ? StorePaths.createGlobMatcher(filePattern)
        : null;
    final results = <FileSearchResult>[];

    for (final name in names) {
      cancellationToken?.throwIfCancellationRequested();

      // Re-apply the caller's scope: findMatchingFilesAsync is explicitly
      // allowed to over-return, and must not be able to widen what the
      // caller asked for.
      if (!StorePaths.matchesGlob(name, matcher) ||
          (!recursive && name.contains('/'))) {
        continue;
      }

      final path = directory.isEmpty
          ? name
          : "${directory.replaceFirst(RegExp(r'/+$'), '')}/$name";
      final content = await readFileAsync(path, cancellationToken);
      if (content == null) {
        continue; // Deleted between enumeration and read.
      }

      final result = scanContent(name, content, regex);
      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }

  /// Returns the names of the files that *may* contain text matching
  /// [regexPattern] and whose names *may* match [filePattern].
  ///
  /// This is the hook a store uses to narrow the search to the files worth
  /// reading. Semantics are deliberately a **superset**: returning a file
  /// that turns out not to match is harmless, because [searchFilesAsync]
  /// re-scans every candidate, while omitting one loses the match. A backend
  /// with a native search index should override this and push [regexPattern]
  /// down to it, widening rather than guessing where the dialect cannot
  /// express the pattern.
  ///
  /// The default implementation has no index to narrow with, so it walks
  /// [listChildrenAsync] and returns every file in scope, leaving
  /// [searchFilesAsync] to read and scan all of them. Overriding
  /// [searchFilesAsync] instead is also supported, but then line numbering is
  /// the store's responsibility (see [splitLines]), and nothing checks it at
  /// runtime.
  ///
  /// Both [regexPattern] and [filePattern] are matched case-insensitively, so
  /// an index that cannot search that way must widen rather than narrow.
  /// Returns file paths relative to [directory], using forward slashes.
  Future<List<String>> findMatchingFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    bool recursive = false,
    CancellationToken? cancellationToken,
  ]) async {
    // No index to narrow with here; a backend with one overrides this.
    final names = <String>[];
    final pending = <String>[''];

    while (pending.isNotEmpty) {
      // Checked here as well as passed down: a store whose listChildrenAsync
      // ignores the token would otherwise let a cancelled walk enumerate the
      // whole hierarchy one listing at a time.
      cancellationToken?.throwIfCancellationRequested();

      final relativeDir = pending.removeLast();
      final trimmed = directory.replaceFirst(RegExp(r'/+$'), '');
      final target = relativeDir.isEmpty
          ? directory
          : (directory.isEmpty ? relativeDir : '$trimmed/$relativeDir');

      for (final entry in await listChildrenAsync(target, cancellationToken)) {
        cancellationToken?.throwIfCancellationRequested();

        final child = relativeDir.isEmpty
            ? entry.name
            : '$relativeDir/${entry.name}';
        if (entry.type == FileStoreEntry.directory) {
          if (recursive) {
            pending.add(child);
          }
        } else {
          names.add(child);
        }
      }
    }

    return names;
  }

  /// Splits [content] into the lines this package's line numbers address.
  ///
  /// This is the published definition of a line for the whole file-access
  /// surface: the `read_lines` and `replace_lines` tools, and every
  /// [FileSearchMatch.lineNumber] reported by [searchFilesAsync], are
  /// coordinates in this list. Each line keeps its terminator (`\r\n`, `\n`,
  /// or a lone `\r`), and the final line has none when the content does not
  /// end with a newline.
  ///
  /// A store that overrides [searchFilesAsync] must number its matches by
  /// this split, otherwise grep and the line editor disagree and an edit
  /// lands on the wrong line.
  static List<String> splitLines(String content) =>
      FileEditor.splitLinesKeepEnds(content);

  /// Finds every line of [content] matching [regex], numbered by
  /// [splitLines].
  ///
  /// This is the numbering primitive [searchFilesAsync] uses, published so a
  /// store that supplies its own [searchFilesAsync] can produce aligned
  /// results rather than re-deriving them. Lines are reported verbatim,
  /// terminator included; the pattern is matched against the line without its
  /// terminator, so an end-anchored pattern behaves the same on CRLF content.
  ///
  /// [fileName] is the name recorded on the result, relative to the searched
  /// directory. Returns `null` when no line matches.
  static FileSearchResult? scanContent(
    String fileName,
    String content,
    RegExp regex,
  ) {
    final lines = splitLines(content);
    final matchingLines = <FileSearchMatch>[];
    String? firstSnippet;
    var lineStartOffset = 0;

    for (var i = 0; i < lines.length; i++) {
      // Match over the line's text only, excluding its terminator.
      final lineText = FileEditor.trimLineTerminator(lines[i]);
      final match = regex.firstMatch(lineText);
      if (match != null) {
        matchingLines.add(
          FileSearchMatch()
            ..lineNumber = i + 1
            ..line = lines[i],
        );

        // Build a context snippet around the first match (+/-50 chars).
        if (firstSnippet == null) {
          final matchedValue = match.group(0) ?? '';
          final charIndex = lineStartOffset + match.start;
          final snippetStart = max(0, charIndex - 50);
          final snippetEnd = min(
            content.length,
            charIndex + matchedValue.length + 50,
          );
          firstSnippet = content.substring(snippetStart, snippetEnd);
        }
      }

      // Advance past this line; its terminator is already part of its length.
      lineStartOffset += lines[i].length;
    }

    if (matchingLines.isEmpty) {
      return null;
    }

    return FileSearchResult()
      ..fileName = fileName
      ..snippet = firstSnippet!
      ..matchingLines = matchingLines;
  }

  /// Ensures a directory exists, creating it if necessary.
  Future<void> createDirectoryAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]);
}
