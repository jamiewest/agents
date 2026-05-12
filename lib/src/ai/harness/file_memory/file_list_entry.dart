import 'file_memory_provider.dart';

/// Represents a file entry returned by the [FileMemoryProvider] list files
/// tool, containing the file name and an optional description.
class FileListEntry {
  FileListEntry();

  /// Name of the file.
  String fileName = '';

  /// Description of the file, or `null` if no description is available.
  String? description;
}
