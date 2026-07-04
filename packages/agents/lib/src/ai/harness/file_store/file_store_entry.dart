import 'agent_file_store.dart';

/// Represents a single direct child of a directory in an [AgentFileStore],
/// returned by [AgentFileStore.listChildrenAsync].
class FileStoreEntry {
  /// Creates an entry with the given [name] and [type].
  ///
  /// [name] is a single path segment, not a full path. [type] is either
  /// [file] or [directory].
  FileStoreEntry(this.name, this.type);

  /// The [type] value for a regular file.
  static const String file = 'file';

  /// The [type] value for a subdirectory.
  static const String directory = 'directory';

  /// The name of the entry (a single path segment relative to the listed
  /// directory).
  final String name;

  /// The entry type, either [file] or [directory].
  final String type;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileStoreEntry && name == other.name && type == other.type;
  }

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => '$type:$name';
}
