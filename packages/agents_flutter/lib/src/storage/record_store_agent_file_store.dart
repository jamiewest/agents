// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:agents/agents.dart';
import 'package:extensions/system.dart';

import 'record_store.dart';

/// A durable [AgentFileStore] persisted through a [RecordStore].
///
/// Replaces the evaporating in-memory defaults for agent file memory and
/// file access. Files are text records in the `agent_files` collection,
/// partitioned by [namespace] (a conversation or channel id) so scopes
/// never see each other's files. Works on native and web alike.
class RecordStoreAgentFileStore extends AgentFileStore {
  /// Creates a [RecordStoreAgentFileStore] for one [namespace].
  RecordStoreAgentFileStore(
    this._records, {
    required this.namespace,
    this._collection = defaultCollection,
  });

  /// The default record collection holding agent files.
  static const String defaultCollection = 'agent_files';

  /// The partition (conversation or channel id) this store serves.
  final String namespace;

  final RecordStore _records;
  final String _collection;

  String _idFor(String normalizedPath) =>
      '$namespace:${normalizedPath.toLowerCase()}';

  @override
  Future<void> writeFileAsync(
    String path,
    String content, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalized = StorePaths.normalizeRelativePath(path);
    await _records.put(_collection, _idFor(normalized), {
      'namespace': namespace,
      'path': normalized,
      'content': content,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<String?> readFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalized = StorePaths.normalizeRelativePath(path);
    final record = await _records.get(_collection, _idFor(normalized));
    return record?['content'] as String?;
  }

  @override
  Future<bool> deleteFileAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalized = StorePaths.normalizeRelativePath(path);
    final id = _idFor(normalized);
    final existed = await _records.get(_collection, id) != null;
    await _records.delete(_collection, id);
    return existed;
  }

  @override
  Future<bool> fileExistsAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    final normalized = StorePaths.normalizeRelativePath(path);
    return await _records.get(_collection, _idFor(normalized)) != null;
  }

  @override
  Future<List<String>> listFilesAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]) async {
    final prefix = _directoryPrefix(directory);
    final files = await _namespaceFiles();
    return [
      for (final (path, _) in files)
        if (_inDirectory(path, prefix)) path.substring(prefix.length),
    ];
  }

  @override
  Future<List<FileStoreEntry>> listChildrenAsync(
    String directory, [
    CancellationToken? cancellationToken,
  ]) async {
    final prefix = _directoryPrefix(directory);
    final directories = <String>{};
    final files = <String>[];
    for (final (path, _) in await _namespaceFiles()) {
      if (!path.toLowerCase().startsWith(prefix.toLowerCase())) continue;
      final remainder = path.substring(prefix.length);
      final separatorIndex = remainder.indexOf('/');
      if (separatorIndex < 0) {
        files.add(remainder);
      } else {
        directories.add(remainder.substring(0, separatorIndex));
      }
    }
    return [
      for (final name in directories)
        FileStoreEntry(name, FileStoreEntry.directory),
      for (final name in files) FileStoreEntry(name, FileStoreEntry.file),
    ];
  }

  @override
  Future<List<FileSearchResult>> searchFilesAsync(
    String directory,
    String regexPattern, [
    String? filePattern,
    bool recursive = false,
    CancellationToken? cancellationToken,
  ]) async {
    final prefix = _directoryPrefix(directory);
    final regex = RegExp(regexPattern, caseSensitive: false);
    final glob = filePattern != null
        ? StorePaths.createGlobMatcher(filePattern)
        : null;

    final results = <FileSearchResult>[];
    for (final (path, content) in await _namespaceFiles()) {
      if (recursive
          ? !path.toLowerCase().startsWith(prefix.toLowerCase())
          : !_inDirectory(path, prefix)) {
        continue;
      }
      final relativeName = path.substring(prefix.length);
      if (!StorePaths.matchesGlob(relativeName, glob)) continue;

      final matches = <FileSearchMatch>[];
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          matches.add(
            FileSearchMatch()
              ..lineNumber = i + 1
              ..line = lines[i],
          );
        }
      }
      if (matches.isNotEmpty) {
        results.add(
          FileSearchResult()
            ..fileName = relativeName
            ..snippet = matches.first.line.trim()
            ..matchingLines = matches,
        );
      }
    }
    return results;
  }

  @override
  Future<void> createDirectoryAsync(
    String path, [
    CancellationToken? cancellationToken,
  ]) async {
    StorePaths.normalizeRelativePath(path, isDirectory: true);
  }

  Future<List<(String path, String content)>> _namespaceFiles() async {
    final records = await _records.query(
      _collection,
      query: RecordQuery(equals: {'namespace': namespace}),
    );
    return [
      for (final record in records)
        (
          record.value['path']! as String,
          record.value['content'] as String? ?? '',
        ),
    ];
  }

  static String _directoryPrefix(String directory) {
    var prefix = StorePaths.normalizeRelativePath(directory, isDirectory: true);
    if (prefix.isNotEmpty && !prefix.endsWith('/')) {
      prefix += '/';
    }
    return prefix;
  }

  static bool _inDirectory(String path, String prefix) {
    final lower = path.toLowerCase();
    if (!lower.startsWith(prefix.toLowerCase())) return false;
    return !path.substring(prefix.length).contains('/');
  }
}
