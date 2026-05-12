import 'file_memory_provider.dart';

/// Options controlling the behavior of [FileMemoryProvider].
class FileMemoryProviderOptions {
  FileMemoryProviderOptions();

  /// Gets or sets custom instructions provided to the agent for using the file
  /// memory tools.
  String? instructions;
}
