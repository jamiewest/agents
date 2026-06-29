/// Configuration options for [AgentMcpSkillsSource].
class AgentMcpSkillsSourceOptions {
  /// Creates MCP skill source options.
  AgentMcpSkillsSourceOptions({
    this.archiveSkillsDirectory,
    this.archiveResourceExtensions,
    this.archiveResourceSearchDepth,
    this.archiveMaxFileCount,
    this.archiveMaxSizeBytes,
    this.archiveMaxUncompressedSizeBytes,
    this.refreshInterval,
  });

  /// Base directory where archive-type skills are extracted.
  final String? archiveSkillsDirectory;

  /// Allowed resource extensions for extracted archive-type skills.
  final Iterable<String>? archiveResourceExtensions;

  /// Maximum resource search depth for extracted archive-type skills.
  final int? archiveResourceSearchDepth;

  /// Maximum number of files extracted from one archive.
  final int? archiveMaxFileCount;

  /// Maximum compressed archive payload size in bytes.
  final int? archiveMaxSizeBytes;

  /// Maximum total extracted file size in bytes.
  final int? archiveMaxUncompressedSizeBytes;

  /// Duration for which discovered skills remain fresh in cache.
  final Duration? refreshInterval;
}
