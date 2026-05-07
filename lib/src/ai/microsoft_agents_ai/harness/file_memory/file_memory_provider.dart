import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../../../semaphore_slim.dart';
import '../../agent_json_utilities.dart';
import '../file_store/agent_file_store.dart';
import '../file_store/file_search_result.dart';
import '../file_store/store_paths.dart';
import 'file_list_entry.dart';
import 'file_memory_provider_options.dart';
import 'file_memory_state.dart';

/// An [AIContextProvider] that provides file-based memory tools to an agent
/// for storing, retrieving, modifying, listing, deleting, and searching files.
///
/// Remarks: The [FileMemoryProvider] enables agents to persist information
/// across interactions using a file-based storage model. Each memory is stored
/// as an individual file with a meaningful name. For large files, a companion
/// description file (suffixed with `_description.md`) can be stored alongside
/// the main file to provide a summary.
class FileMemoryProvider extends AIContextProvider implements Disposable {
  /// Initializes a new instance of the [FileMemoryProvider] class.
  FileMemoryProvider(
    AgentFileStore? fileStore, {
    FileMemoryState Function(AgentSession?)? stateInitializer,
    FileMemoryProviderOptions? options,
  }) {
    if (fileStore == null) {
      throw ArgumentError.notNull('fileStore');
    }

    _fileStore = fileStore;
    _instructions = options?.instructions ?? defaultInstructions;
    _sessionState = ProviderSessionState<FileMemoryState>(
      stateInitializer ?? (_) => FileMemoryState(),
      runtimeType.toString(),
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  static const String descriptionSuffix = '_description.md';
  static const String memoryIndexFileName = 'memories.md';
  static const int maxIndexEntries = 50;

  static const String defaultInstructions = '''
## File Based Memory
You have access to a session-scoped, file-based memory system via the `FileMemory_*` tools for storing and retrieving information across interactions.
These files act as your working memory for the current session and are isolated from other sessions.
Use these tools to store plans, memories, processing results, or downloaded data.

- Use descriptive file names (e.g., "projectarchitecture.md", "userpreferences.md").
- Include a description when saving a file to help with future discovery.
- Before starting new tasks, use FileMemory_ListFiles and FileMemory_SearchFiles to check for relevant existing memories.
- Keep memories up-to-date by overwriting files when information changes.
- When you receive large amounts of data (e.g., downloaded web pages, API responses, research results),
  save them to files if they will be required later, so that they are not lost when older context is compacted or truncated.
  This ensures important data remains accessible across long-running sessions.
''';

  late final AgentFileStore _fileStore;
  late final ProviderSessionState<FileMemoryState> _sessionState;
  final SemaphoreSlim _writeLock = SemaphoreSlim(1, 1);
  late final String _instructions;
  List<String>? _stateKeys;
  List<AITool>? _tools;

  @override
  List<String> get stateKeys => _stateKeys ??= [_sessionState.stateKey];

  /// Releases the resources used by the [FileMemoryProvider].
  @override
  void dispose() {
    _writeLock.dispose();
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(context.session);

    if (state.workingFolder.isNotEmpty) {
      await _fileStore.createDirectoryAsync(
        state.workingFolder,
        cancellationToken,
      );
    }

    final aiContext = AIContext()
      ..instructions = _instructions
      ..tools = _tools ??= createTools();

    final indexPath = combinePaths(state.workingFolder, memoryIndexFileName);
    final indexContent = await _fileStore.readFileAsync(
      indexPath,
      cancellationToken,
    );
    if (indexContent != null && indexContent.trim().isNotEmpty) {
      aiContext.messages = [
        ChatMessage.fromText(
          ChatRole.user,
          'The following is your memory index - a list of files you have previously saved. '
          'You can read any of these files using the FileMemory_ReadFile tool.\n\n'
          '$indexContent',
        ),
      ];
    }

    return aiContext;
  }

  /// Save a memory file with the given name and content. Overwrites the file
  /// if it already exists. Include a description for large files to provide a
  /// summary that helps with discovery.
  Future<String> saveFileAsync(
    String fileName,
    String content, {
    String? description,
    CancellationToken? cancellationToken,
  }) async {
    if (isInternalFile(fileName)) {
      throw ArgumentError(
        'The provided file name is reserved by the system for internal use. Please choose a different file name.',
        'fileName',
      );
    }

    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final path = resolvePath(state.workingFolder, fileName);

    await _writeLock.waitAsync(cancellationToken);
    try {
      await _fileStore.writeFileAsync(path, content, cancellationToken);

      final descPath = resolvePath(
        state.workingFolder,
        getDescriptionFileName(fileName),
      );
      if (description != null && description.trim().isNotEmpty) {
        await _fileStore.writeFileAsync(
          descPath,
          description,
          cancellationToken,
        );
      } else {
        await _fileStore.deleteFileAsync(descPath, cancellationToken);
      }

      final result = description == null || description.trim().isEmpty
          ? "File '$fileName' saved."
          : "File '$fileName' saved with description.";
      await rebuildMemoryIndexAsync(state, cancellationToken);
      return result;
    } finally {
      _writeLock.release();
    }
  }

  /// Read the content of a memory file by name. Returns the file content or a
  /// message indicating the file was not found.
  Future<String> readFileAsync(
    String fileName, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final path = resolvePath(state.workingFolder, fileName);
    final content = await _fileStore.readFileAsync(path, cancellationToken);
    return content ?? "File '$fileName' not found.";
  }

  /// Delete a memory file by name. Also removes its companion description file
  /// if one exists.
  Future<String> deleteFileAsync(
    String fileName, {
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final path = resolvePath(state.workingFolder, fileName);

    await _writeLock.waitAsync(cancellationToken);
    try {
      final deleted = await _fileStore.deleteFileAsync(path, cancellationToken);

      final descPath = resolvePath(
        state.workingFolder,
        getDescriptionFileName(fileName),
      );
      await _fileStore.deleteFileAsync(descPath, cancellationToken);

      await rebuildMemoryIndexAsync(state, cancellationToken);
      return deleted
          ? "File '$fileName' deleted."
          : "File '$fileName' not found.";
    } finally {
      _writeLock.release();
    }
  }

  /// List all memory files with their descriptions (if available).
  /// Description files are not shown separately.
  Future<List<FileListEntry>> listFilesAsync({
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final fileNames = await _fileStore.listFilesAsync(
      state.workingFolder,
      cancellationToken,
    );

    final descriptionFileSet = <String>{};
    for (final file in fileNames) {
      if (file.toLowerCase().endsWith(descriptionSuffix)) {
        descriptionFileSet.add(file.toLowerCase());
      }
    }

    final entries = <FileListEntry>[];
    for (final file in fileNames) {
      if (descriptionFileSet.contains(file.toLowerCase())) {
        continue;
      }

      if (isInternalFile(file)) {
        continue;
      }

      String? fileDescription;
      final descFileName = getDescriptionFileName(file);
      if (descriptionFileSet.contains(descFileName.toLowerCase())) {
        final descPath = combinePaths(state.workingFolder, descFileName);
        fileDescription = await _fileStore.readFileAsync(
          descPath,
          cancellationToken,
        );
      }

      entries.add(
        FileListEntry()
          ..fileName = file
          ..description = fileDescription,
      );
    }

    return entries;
  }

  /// Search memory file contents using a regular expression pattern
  /// (case-insensitive). Optionally filter which files to search using a glob
  /// pattern.
  Future<List<FileSearchResult>> searchFilesAsync(
    String regexPattern, {
    String? filePattern,
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final pattern = filePattern == null || filePattern.trim().isEmpty
        ? null
        : filePattern;
    final results = await _fileStore.searchFilesAsync(
      state.workingFolder,
      regexPattern,
      pattern,
      cancellationToken,
    );

    return results.where((r) => !isInternalFile(r.fileName)).toList();
  }

  List<AITool> createTools() {
    return [
      AIFunctionFactory.create(
        name: 'FileMemory_SaveFile',
        description:
            'Save a memory file with the given name and content. Overwrites the file if it already exists. Include a description for large files to provide a summary that helps with discovery.',
        parametersSchema: _objectSchema(
          {
            'fileName': 'The name of the file to save.',
            'content': 'The content to write to the file.',
            'description':
                'An optional description of the file contents for discovery.',
          },
          required: ['fileName', 'content'],
        ),
        callback: (arguments, {cancellationToken}) {
          return saveFileAsync(
            _getRequiredString(arguments, 'fileName'),
            _getRequiredString(arguments, 'content'),
            description: _getOptionalString(arguments, 'description'),
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: 'FileMemory_ReadFile',
        description:
            'Read the content of a memory file by name. Returns the file content or a message indicating the file was not found.',
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
        name: 'FileMemory_DeleteFile',
        description:
            'Delete a memory file by name. Also removes its companion description file if one exists.',
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
        name: 'FileMemory_ListFiles',
        description:
            'List all memory files with their descriptions (if available). Description files are not shown separately.',
        callback: (arguments, {cancellationToken}) {
          return listFilesAsync(cancellationToken: cancellationToken);
        },
      ),
      AIFunctionFactory.create(
        name: 'FileMemory_SearchFiles',
        description:
            'Search memory file contents using a regular expression pattern (case-insensitive). Optionally filter which files to search using a glob pattern (e.g., "*.md", "research*"). Returns matching file names, content snippets, and matching lines with line numbers.',
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

  /// Rebuilds the `memories.md` index file by listing all user files in the
  /// working folder, reading their companion description files, and writing a
  /// markdown summary capped at [maxIndexEntries] entries.
  Future<void> rebuildMemoryIndexAsync(
    FileMemoryState state,
    CancellationToken? cancellationToken,
  ) async {
    final fileNames = await _fileStore.listFilesAsync(
      state.workingFolder,
      cancellationToken,
    );
    final sortedFiles = fileNames.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final sb = StringBuffer()
      ..writeln('# Memory Index')
      ..writeln();

    var count = 0;
    for (final file in sortedFiles) {
      if (isInternalFile(file)) {
        continue;
      }

      if (count >= maxIndexEntries) {
        break;
      }

      final descFileName = getDescriptionFileName(file);
      final descPath = combinePaths(state.workingFolder, descFileName);
      final description = await _fileStore.readFileAsync(
        descPath,
        cancellationToken,
      );

      if (description != null && description.trim().isNotEmpty) {
        sb.writeln('- **$file**: $description');
      } else {
        sb.writeln('- **$file**');
      }

      count++;
    }

    final indexPath = combinePaths(state.workingFolder, memoryIndexFileName);
    await _fileStore.writeFileAsync(
      indexPath,
      sb.toString(),
      cancellationToken,
    );
  }

  static String getDescriptionFileName(String fileName) {
    final extIndex = fileName.lastIndexOf('.');
    if (extIndex > 0) {
      return '${fileName.substring(0, extIndex)}$descriptionSuffix';
    }

    return '$fileName$descriptionSuffix';
  }

  /// Returns `true` if the file is an internal system file that should be
  /// hidden from user-facing operations (description sidecars and the memory
  /// index).
  static bool isInternalFile(String fileName) {
    return fileName.toLowerCase().endsWith(descriptionSuffix) ||
        fileName.toLowerCase() == memoryIndexFileName;
  }

  static String resolvePath(String workingFolder, String fileName) {
    final normalizedFileName = StorePaths.normalizeRelativePath(fileName);
    final normalizedWorkingFolder = workingFolder.replaceAll('\\', '/');
    return combinePaths(normalizedWorkingFolder, normalizedFileName);
  }

  static String combinePaths(String basePath, String relativePath) {
    if (basePath.isEmpty) {
      return relativePath;
    }

    if (relativePath.isEmpty) {
      return basePath;
    }

    return '${_trimRightSlash(basePath)}/${_trimLeftSlash(relativePath)}';
  }

  static String _trimRightSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static String _trimLeftSlash(String value) {
    return value.replaceFirst(RegExp(r'^/+'), '');
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
