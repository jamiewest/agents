import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:extensions/system.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:path/path.dart' as p;

import '../ai/skills/agent_skill.dart';
import '../ai/skills/agent_skill_frontmatter.dart';
import '../ai/skills/agent_skill_resource.dart';
import '../ai/skills/agent_skills_source.dart';
import '../ai/skills/file/agent_file_skills_source.dart';
import '../ai/skills/file/agent_file_skills_source_options.dart';
import 'agent_mcp_skill_resource.dart';
import 'agent_mcp_skills_source_options.dart';

/// An [AgentSkillsSource] that discovers Agent Skills exposed over MCP.
class AgentMcpSkillsSource extends AgentSkillsSource {
  /// Creates an MCP-backed skills source.
  AgentMcpSkillsSource(this.client, {AgentMcpSkillsSourceOptions? options})
    : options = options ?? AgentMcpSkillsSourceOptions();

  /// SEP-2640 canonical skill index URI.
  static const String indexUri = 'skill://index.json';

  /// The MCP client used to read skill resources.
  final mcp.McpClient client;

  /// Source configuration.
  final AgentMcpSkillsSourceOptions options;

  List<AgentSkill>? _cachedSkills;
  DateTime? _lastRefreshedUtc;
  Future<List<AgentSkill>>? _refreshFuture;
  String? _archiveSkillsDirectory;

  @override
  Future<List<AgentSkill>> getSkills({
    CancellationToken? cancellationToken,
  }) async {
    final cached = _tryGetCachedSkills();
    if (cached != null) {
      return cached;
    }

    final existing = _refreshFuture;
    if (existing != null) {
      return existing;
    }

    final refresh = _getCoreSkills(cancellationToken ?? CancellationToken.none);
    _refreshFuture = refresh;
    try {
      final skills = await refresh;
      _cachedSkills = skills;
      _lastRefreshedUtc = DateTime.now().toUtc();
      return skills;
    } finally {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
      }
    }
  }

  List<AgentSkill>? _tryGetCachedSkills() {
    final interval = options.refreshInterval;
    final cached = _cachedSkills;
    final refreshed = _lastRefreshedUtc;
    if (interval == null || cached == null || refreshed == null) {
      return null;
    }
    return DateTime.now().toUtc().difference(refreshed) < interval
        ? cached
        : null;
  }

  Future<List<AgentSkill>> _getCoreSkills(
    CancellationToken cancellationToken,
  ) async {
    cancellationToken.throwIfCancellationRequested();
    final index = await _tryReadIndex();
    cancellationToken.throwIfCancellationRequested();

    final entries = index?.skills ?? const <McpSkillIndexEntry>[];
    final skillMdEntries = <McpSkillIndexEntry>[];
    final archiveEntries = <McpSkillIndexEntry>[];
    for (final entry in entries) {
      switch ((entry.type ?? '').toLowerCase()) {
        case 'skill-md':
          skillMdEntries.add(entry);
        case 'archive':
          archiveEntries.add(entry);
      }
    }

    return [
      ..._loadSkillMdEntries(skillMdEntries),
      ...await _ArchiveEntryLoader(client, options).load(
        archiveEntries,
        archiveSkillsDirectory: _archiveSkillsDirectory,
        onArchiveSkillsDirectoryResolved: (directory) {
          _archiveSkillsDirectory = directory;
        },
        cancellationToken: cancellationToken,
      ),
    ];
  }

  Future<McpSkillIndex?> _tryReadIndex() async {
    mcp.ReadResourceResult result;
    try {
      result = await client.readResource(
        const mcp.ReadResourceRequest(uri: indexUri),
      );
    } catch (_) {
      return null;
    }

    final text = result.contents
        .whereType<mcp.TextResourceContents>()
        .map((content) => content.text)
        .firstWhere((text) => text.trim().isNotEmpty, orElse: () => '');
    if (text.isEmpty) {
      return null;
    }

    try {
      return McpSkillIndex.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  List<AgentSkill> _loadSkillMdEntries(List<McpSkillIndexEntry> entries) {
    final skills = <AgentSkill>[];
    for (final entry in entries) {
      if ((entry.url ?? '').trim().isEmpty) {
        continue;
      }
      try {
        skills.add(
          AgentMcpSkill(
            AgentSkillFrontmatter(entry.name ?? '', entry.description ?? ''),
            entry.url!,
            client,
          ),
        );
      } on ArgumentError {
        continue;
      }
    }
    return skills;
  }
}

/// An [AgentSkill] discovered from MCP skill metadata.
class AgentMcpSkill extends AgentSkill {
  /// Creates an MCP-backed skill.
  AgentMcpSkill(this.frontmatter, this.skillMdUri, this.client)
    : skillRootUri = _computeSkillRootUri(skillMdUri);

  static const String _skillMdSuffix = 'SKILL.md';

  @override
  final AgentSkillFrontmatter frontmatter;

  /// The MCP URI for this skill's `SKILL.md`.
  final String skillMdUri;

  /// The root URI used to resolve sibling resources.
  final String skillRootUri;

  /// The MCP client used to fetch resources.
  final mcp.McpClient client;

  String? _content;

  @override
  String get content => _content ?? '';

  @override
  Future<String> getContent({CancellationToken? cancellationToken}) async {
    final cached = _content;
    if (cached != null) {
      return cached;
    }
    cancellationToken?.throwIfCancellationRequested();
    final result = await client.readResource(
      mcp.ReadResourceRequest(uri: skillMdUri),
    );
    cancellationToken?.throwIfCancellationRequested();

    final text = result.contents
        .whereType<mcp.TextResourceContents>()
        .map((content) => content.text)
        .join('\n');
    if (text.isEmpty) {
      throw StateError(
        "The MCP server returned no text content for '$skillMdUri'.",
      );
    }
    return _content = text;
  }

  @override
  Future<AgentSkillResource?> getResource(
    String name, {
    CancellationToken? cancellationToken,
  }) async {
    if (name.trim().isEmpty) {
      return null;
    }

    cancellationToken?.throwIfCancellationRequested();
    try {
      final result = await client.readResource(
        mcp.ReadResourceRequest(uri: '$skillRootUri$name'),
      );
      cancellationToken?.throwIfCancellationRequested();
      if (result.contents.isEmpty) {
        return null;
      }
      return AgentMcpSkillResource(name, result);
    } catch (_) {
      return null;
    }
  }

  static String _computeSkillRootUri(String skillMdUri) {
    if (skillMdUri.endsWith(_skillMdSuffix)) {
      return skillMdUri.substring(0, skillMdUri.length - _skillMdSuffix.length);
    }
    return skillMdUri.endsWith('/') ? skillMdUri : '$skillMdUri/';
  }
}

/// DTO for `skill://index.json`.
class McpSkillIndex {
  /// Creates a skill index.
  McpSkillIndex({this.schema, List<McpSkillIndexEntry>? skills})
    : skills = skills ?? const [];

  /// Schema identifier, if present.
  final String? schema;

  /// Advertised skills.
  final List<McpSkillIndexEntry> skills;

  /// Parses a skill index from JSON.
  factory McpSkillIndex.fromJson(Map<String, dynamic> json) {
    final skills = json['skills'];
    return McpSkillIndex(
      schema: json[r'$schema'] as String?,
      skills: skills is List
          ? [
              for (final entry in skills)
                if (entry is Map)
                  McpSkillIndexEntry.fromJson(entry.cast<String, dynamic>()),
            ]
          : const [],
    );
  }
}

/// A single skill discovery index entry.
class McpSkillIndexEntry {
  /// Creates a skill index entry.
  McpSkillIndexEntry({
    this.name,
    this.type,
    this.description,
    this.url,
    this.digest,
  });

  /// Skill name.
  final String? name;

  /// Distribution type.
  final String? type;

  /// Skill description.
  final String? description;

  /// MCP resource URI.
  final String? url;

  /// Optional digest from non-MCP indexes.
  final String? digest;

  /// Parses a skill index entry from JSON.
  factory McpSkillIndexEntry.fromJson(Map<String, dynamic> json) {
    return McpSkillIndexEntry(
      name: json['name'] as String?,
      type: json['type'] as String?,
      description: json['description'] as String?,
      url: json['url'] as String?,
      digest: json['digest'] as String?,
    );
  }
}

class _ArchiveEntryLoader {
  _ArchiveEntryLoader(this.client, this.options);

  static const int _defaultMaxArchiveSizeBytes = 1024 * 1024;
  static const int _defaultMaxFileCount = 20;
  static const int _defaultMaxUncompressedSizeBytes = 1024 * 1024;

  final mcp.McpClient client;
  final AgentMcpSkillsSourceOptions options;

  Future<List<AgentSkill>> load(
    List<McpSkillIndexEntry> entries, {
    required String? archiveSkillsDirectory,
    required void Function(String directory) onArchiveSkillsDirectoryResolved,
    required CancellationToken cancellationToken,
  }) async {
    final validEntries = entries.where(_isValidArchiveEntry).toList();
    _reconcileArchiveSkillDirectories(archiveSkillsDirectory, validEntries);

    if (validEntries.isEmpty) {
      return const [];
    }

    final resolvedDirectory =
        archiveSkillsDirectory ??
        options.archiveSkillsDirectory ??
        p.join(Directory.current.path, _newDirectoryId());
    onArchiveSkillsDirectoryResolved(resolvedDirectory);
    Directory(resolvedDirectory).createSync(recursive: true);

    final skillDirectories = <String>[];
    for (final entry in validEntries) {
      cancellationToken.throwIfCancellationRequested();
      final extracted = await _tryDownloadAndExtractSkill(
        entry,
        resolvedDirectory,
      );
      if (extracted != null) {
        skillDirectories.add(extracted);
      }
    }

    if (skillDirectories.isEmpty) {
      return const [];
    }

    final fileOptions = AgentFileSkillsSourceOptions()
      ..allowedScriptExtensions = const []
      ..allowedResourceExtensions =
          options.archiveResourceExtensions ?? _defaultArchiveResourceExtensions
      ..resourceDirectories = const ['.']
      ..resourceSearchDepth = options.archiveResourceSearchDepth ?? 2;

    return AgentFileSkillsSource(
      skillDirectories,
      options: fileOptions,
    ).getSkills(cancellationToken: cancellationToken);
  }

  Future<String?> _tryDownloadAndExtractSkill(
    McpSkillIndexEntry entry,
    String archiveSkillsDirectory,
  ) async {
    final skillDirectory = p.join(archiveSkillsDirectory, entry.name!);
    if (!_isPathContainedIn(archiveSkillsDirectory, skillDirectory)) {
      return null;
    }

    if (!_tryDeleteDirectory(skillDirectory)) {
      return null;
    }

    final download = await _downloadSkillBytes(entry);
    if (download == null) {
      return null;
    }

    final (bytes, mimeType) = download;
    final format = _detectArchiveFormat(bytes, mimeType, entry.url);
    if (format == _ArchiveFormat.unknown) {
      return null;
    }

    try {
      _extractArchive(bytes, format, skillDirectory);
      return skillDirectory;
    } catch (_) {
      _tryDeleteDirectory(skillDirectory);
      return null;
    }
  }

  Future<(Uint8List, String?)?> _downloadSkillBytes(
    McpSkillIndexEntry entry,
  ) async {
    mcp.ReadResourceResult result;
    try {
      result = await client.readResource(
        mcp.ReadResourceRequest(uri: entry.url!),
      );
    } catch (_) {
      return null;
    }

    mcp.BlobResourceContents? blob;
    for (final content in result.contents) {
      if (content is mcp.BlobResourceContents) {
        blob = content;
        break;
      }
    }
    if (blob == null) {
      return null;
    }

    final bytes = base64Decode(blob.blob);
    final maxSize = options.archiveMaxSizeBytes ?? _defaultMaxArchiveSizeBytes;
    if (bytes.isEmpty || bytes.length > maxSize) {
      return null;
    }
    return (Uint8List.fromList(bytes), blob.mimeType);
  }

  bool _isValidArchiveEntry(McpSkillIndexEntry entry) {
    final name = entry.name;
    if (name == null ||
        name.trim().isEmpty ||
        name.trim().replaceAll('.', '').isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(name)) {
      return false;
    }
    final (validName, _) = AgentSkillFrontmatter.validateName(name);
    return validName && (entry.url ?? '').trim().isNotEmpty;
  }

  void _reconcileArchiveSkillDirectories(
    String? archiveSkillsDirectory,
    List<McpSkillIndexEntry> entries,
  ) {
    if (archiveSkillsDirectory == null ||
        !Directory(archiveSkillsDirectory).existsSync()) {
      return;
    }

    final advertised = entries.map((entry) => entry.name!).toSet();
    for (final directory in Directory(archiveSkillsDirectory).listSync()) {
      if (directory is! Directory) {
        continue;
      }
      if (entries.isEmpty || !advertised.contains(p.basename(directory.path))) {
        _tryDeleteDirectory(directory.path);
      }
    }
  }

  void _extractArchive(
    Uint8List bytes,
    _ArchiveFormat format,
    String targetDirectory,
  ) {
    final archive = switch (format) {
      _ArchiveFormat.zip => ZipDecoder().decodeBytes(bytes),
      _ArchiveFormat.tar => TarDecoder().decodeBytes(bytes),
      _ArchiveFormat.tarGz => TarDecoder().decodeBytes(
        Uint8List.fromList(GZipDecoder().decodeBytes(bytes)),
      ),
      _ArchiveFormat.unknown => throw UnsupportedError(
        'Unknown archive format.',
      ),
    };

    Directory(targetDirectory).createSync(recursive: true);
    final fullTarget = p.canonicalize(targetDirectory);
    var fileCount = 0;
    var uncompressedSize = 0;
    final maxFileCount = options.archiveMaxFileCount ?? _defaultMaxFileCount;
    final maxUncompressedSize =
        options.archiveMaxUncompressedSizeBytes ??
        _defaultMaxUncompressedSizeBytes;

    for (final file in archive.files) {
      if (!file.isFile || file.isSymbolicLink) {
        continue;
      }
      fileCount++;
      if (fileCount > maxFileCount) {
        throw StateError('Skill archive exceeds the maximum file count.');
      }
      final destination = _resolveDestination(fullTarget, file.name);
      if (destination == null) {
        continue;
      }
      final content = file.content;
      uncompressedSize += content.length;
      if (uncompressedSize > maxUncompressedSize) {
        throw StateError('Skill archive exceeds the maximum extracted size.');
      }
      File(destination)
        ..createSync(recursive: true)
        ..writeAsBytesSync(content, flush: true);
    }
  }
}

const List<String> _defaultArchiveResourceExtensions = [
  '.md',
  '.json',
  '.yaml',
  '.yml',
  '.csv',
  '.xml',
  '.txt',
  '.py',
  '.js',
  '.sh',
  '.ps1',
  '.cs',
  '.csx',
];

enum _ArchiveFormat { unknown, zip, tar, tarGz }

_ArchiveFormat _detectArchiveFormat(
  List<int> bytes,
  String? mediaType,
  String? url,
) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    return _ArchiveFormat.tarGz;
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07)) {
    return _ArchiveFormat.zip;
  }

  final media = mediaType?.trim().toLowerCase();
  if (media == 'application/zip' || media == 'application/x-zip-compressed') {
    return _ArchiveFormat.zip;
  }
  if (media == 'application/gzip' ||
      media == 'application/x-gzip' ||
      media == 'application/x-compressed-tar') {
    return _ArchiveFormat.tarGz;
  }
  if (media == 'application/x-tar' || media == 'application/tar') {
    return _ArchiveFormat.tar;
  }

  final lowerUrl = (url ?? '').toLowerCase();
  if (lowerUrl.endsWith('.zip')) {
    return _ArchiveFormat.zip;
  }
  if (lowerUrl.endsWith('.tar.gz') || lowerUrl.endsWith('.tgz')) {
    return _ArchiveFormat.tarGz;
  }
  if (lowerUrl.endsWith('.tar')) {
    return _ArchiveFormat.tar;
  }
  return _ArchiveFormat.unknown;
}

String? _resolveDestination(String fullTarget, String entryPath) {
  if (entryPath.trim().isEmpty ||
      entryPath.startsWith('/') ||
      entryPath.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(entryPath)) {
    return null;
  }

  final normalized = entryPath
      .replaceAll(r'\', '/')
      .replaceAll(RegExp(r'^/+'), '');
  if (normalized.isEmpty) {
    return null;
  }

  final destination = p.canonicalize(p.join(fullTarget, normalized));
  return _isPathContainedIn(fullTarget, destination) ? destination : null;
}

bool _isPathContainedIn(String parentDirectory, String candidatePath) {
  final parent = p.canonicalize(parentDirectory);
  final candidate = p.canonicalize(candidatePath);
  final prefix = parent.endsWith(p.separator)
      ? parent
      : '$parent${p.separator}';
  return candidate.startsWith(prefix);
}

bool _tryDeleteDirectory(String directory) {
  try {
    final dir = Directory(directory);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    return true;
  } catch (_) {
    return false;
  }
}

String _newDirectoryId() {
  final random = Random.secure().nextInt(1 << 32).toRadixString(16);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}_$random';
}
