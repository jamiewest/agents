import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../file_store/agent_file_store.dart';
import '../file_store/file_search_result.dart';
import '../file_store/store_paths.dart';
import 'file_access_provider_options.dart';

/// An [AIContextProvider] that provides file access tools to an agent for
/// saving, reading, deleting, listing, and searching files.
///
/// Remarks: The [FileAccessProvider] gives agents the ability to work with
/// files in a folder that the user has granted access to. Unlike
/// FileMemoryProvider, which provides session-scoped memory that may be
/// isolated per session, [FileAccessProvider] operates on a shared,
/// persistent folder whose contents are visible across sessions and agents.
/// This makes it suitable for reading input data, writing output artifacts,
/// and working with files that have a lifetime beyond any single agent
/// session.
class FileAccessProvider extends AIContextProvider {
  /// Initializes a new instance of the [FileAccessProvider] class.
  ///
  /// [fileStore] The file store implementation used for storage operations.
  /// The store should already be scoped to the desired folder or storage
  /// location.
  FileAccessProvider(
    AgentFileStore? fileStore, {
    FileAccessProviderOptions? options,
  }) {
    if (fileStore == null) {
      throw ArgumentError.notNull('fileStore');
    }

    _fileStore = fileStore;
    _instructions = options?.instructions ?? defaultInstructions;
  }

  static const String defaultInstructions = '''
## File Access
You have access to a shared file storage area via the `FileAccess_*` tools for reading, writing, and managing files.
These files persist beyond the current session and may be shared across sessions or agents.
Use these tools to read input data provided by the user, write output artifacts, and manage any files the user has asked you to work with.

- Never delete or overwrite existing files unless the user has explicitly asked you to do so.
''';

  late final AgentFileStore _fileStore;

  late final String _instructions;

  List<AITool>? _tools;

  @override
  List<String> get stateKeys => const [];

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) {
    return Future.value(
      AIContext()
        ..instructions = _instructions
        ..tools = _tools ??= createTools(),
    );
  }

  /// Save a file with the given name and content. By default, does not
  /// overwrite an existing file unless [overwrite] is set to true.
  Future<String> saveFileAsync(
    String fileName,
    String content, {
    bool overwrite = false,
    CancellationToken? cancellationToken,
  }) async {
    final path = StorePaths.normalizeRelativePath(fileName);

    if (!overwrite &&
        await _fileStore.fileExistsAsync(path, cancellationToken)) {
      return "File '$fileName' already exists. To replace it, save again with overwrite set to true.";
    }

    await _fileStore.writeFileAsync(path, content, cancellationToken);
    return "File '$fileName' saved.";
  }

  /// Read the content of a file by name. Returns the file content or a message
  /// indicating the file was not found.
  Future<String> readFileAsync(
    String fileName, {
    CancellationToken? cancellationToken,
  }) async {
    final path = StorePaths.normalizeRelativePath(fileName);
    final content = await _fileStore.readFileAsync(path, cancellationToken);
    return content ?? "File '$fileName' not found.";
  }

  /// Delete a file by name.
  Future<String> deleteFileAsync(
    String fileName, {
    CancellationToken? cancellationToken,
  }) async {
    final path = StorePaths.normalizeRelativePath(fileName);
    final deleted = await _fileStore.deleteFileAsync(path, cancellationToken);
    return deleted
        ? "File '$fileName' deleted."
        : "File '$fileName' not found.";
  }

  /// List all file names.
  Future<List<String>> listFilesAsync({
    CancellationToken? cancellationToken,
  }) async {
    final fileNames = await _fileStore.listFilesAsync('', cancellationToken);
    return fileNames.toList();
  }

  /// Search file contents using a regular expression pattern
  /// (case-insensitive). Optionally filter which files to search using a glob
  /// pattern.
  Future<List<FileSearchResult>> searchFilesAsync(
    String regexPattern, {
    String? filePattern,
    CancellationToken? cancellationToken,
  }) async {
    final pattern = filePattern == null || filePattern.trim().isEmpty
        ? null
        : filePattern;
    final results = await _fileStore.searchFilesAsync(
      '',
      regexPattern,
      pattern,
      cancellationToken,
    );
    return results.toList();
  }

  List<AITool> createTools() {
    return [
      AIFunctionFactory.create(
        name: 'FileAccess_SaveFile',
        description:
            'Save a file with the given name and content. By default, does not overwrite an existing file unless overwrite is set to true.',
        parametersSchema: _objectSchema(
          {
            'fileName': 'The name of the file to save.',
            'content': 'The content to write to the file.',
            'overwrite': 'Whether to overwrite the file if it already exists.',
          },
          required: ['fileName', 'content'],
        ),
        callback: (arguments, {cancellationToken}) {
          return saveFileAsync(
            _getRequiredString(arguments, 'fileName'),
            _getRequiredString(arguments, 'content'),
            overwrite: _getOptionalBool(arguments, 'overwrite') ?? false,
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: 'FileAccess_ReadFile',
        description:
            'Read the content of a file by name. Returns the file content or a message indicating the file was not found.',
        parametersSchema: _objectSchema({
          'fileName': 'The name of the file to read.',
        }),
        callback: (arguments, {cancellationToken}) {
          return readFileAsync(
            _getRequiredString(arguments, 'fileName'),
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: 'FileAccess_DeleteFile',
        description: 'Delete a file by name.',
        parametersSchema: _objectSchema({
          'fileName': 'The name of the file to delete.',
        }),
        callback: (arguments, {cancellationToken}) {
          return deleteFileAsync(
            _getRequiredString(arguments, 'fileName'),
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: 'FileAccess_ListFiles',
        description: 'List all file names.',
        callback: (arguments, {cancellationToken}) {
          return listFilesAsync(cancellationToken: cancellationToken);
        },
      ),
      AIFunctionFactory.create(
        name: 'FileAccess_SearchFiles',
        description:
            'Search file contents using a regular expression pattern (case-insensitive). Optionally filter which files to search using a glob pattern (e.g., "*.md", "research*"). Returns matching file names, snippets, and matching lines with line numbers.',
        parametersSchema: _objectSchema(
          {
            'regexPattern':
                'A regular expression pattern to match against file contents.',
            'filePattern':
                'An optional glob pattern to filter which files are searched.',
          },
          required: ['regexPattern'],
        ),
        callback: (arguments, {cancellationToken}) {
          return searchFilesAsync(
            _getRequiredString(arguments, 'regexPattern'),
            filePattern: _getOptionalString(arguments, 'filePattern'),
            cancellationToken: cancellationToken,
          );
        },
      ),
    ];
  }

  static String _getRequiredString(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value is String) {
      return value;
    }
    throw ArgumentError.value(value, name, 'Expected a string value.');
  }

  static String? _getOptionalString(
    AIFunctionArguments arguments,
    String name,
  ) {
    final value = arguments[name];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw ArgumentError.value(value, name, 'Expected a string value.');
  }

  static bool? _getOptionalBool(AIFunctionArguments arguments, String name) {
    final value = arguments[name];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    throw ArgumentError.value(value, name, 'Expected a boolean value.');
  }

  static Map<String, dynamic> _objectSchema(
    Map<String, String> properties, {
    List<String>? required,
  }) {
    return {
      'type': 'object',
      'properties': {
        for (final entry in properties.entries)
          entry.key: {'description': entry.value},
      },
      'required': required ?? properties.keys.toList(),
    };
  }
}
