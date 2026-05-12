import 'file_memory_provider.dart';

/// Represents a file entry returned by the [FileMemoryProvider] list files
/// tool, containing the file name and an optional description.
class FileListEntry {
  FileListEntry();

  /// Gets or sets the name of the file.
  String fileName = '';

  /// Gets or sets the description of the file, or `null` if no description is
  /// available.
  String? description;
}
