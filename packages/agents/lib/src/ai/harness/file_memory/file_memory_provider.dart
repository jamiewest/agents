import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:pool/pool.dart';

import '../../../abstractions/agent_session.dart';
import '../../../abstractions/ai_agent.dart';
import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../../../abstractions/provider_session_state.dart';
import '../../agent_json_utilities.dart';
import '../file_store/agent_file_store.dart';
import '../file_store/file_editor.dart';
import '../file_store/file_line_edit.dart';
import '../file_store/file_search_result.dart';
import '../file_store/store_paths.dart';
import 'file_list_entry.dart';
import 'file_memory_provider_options.dart';
import 'file_memory_state.dart';
import 'package:agents/src/abstractions/invoking_context.dart';

/// An [AIContextProvider] that provides file-based memory tools to an agent
/// for storing, retrieving, modifying, listing, deleting, and searching files.
///
/// The [FileMemoryProvider] enables agents to persist information across
/// interactions using a file-based storage model. Each memory is stored as an
/// individual file with a meaningful name. For large files, a companion
/// description file (suffixed with `_description.md`) can be stored alongside
/// the main file to provide a summary.
class FileMemoryProvider extends AIContextProvider implements Disposable {
  /// Creates a [FileMemoryProvider] using [fileStore].
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
      stateRehydrator: FileMemoryState.fromJson,
      jsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  /// The name of the tool that writes a memory file.
  static const String writeToolName = 'file_memory_write';

  /// The name of the tool that reads a memory file.
  static const String readFileToolName = 'file_memory_read';

  /// The name of the tool that deletes a memory file.
  static const String deleteFileToolName = 'file_memory_delete';

  /// The name of the tool that lists memory files.
  static const String lsToolName = 'file_memory_ls';

  /// The name of the tool that searches memory file contents.
  static const String grepToolName = 'file_memory_grep';

  /// The name of the tool that replaces occurrences of a substring within a
  /// memory file.
  static const String replaceToolName = 'file_memory_replace';

  /// The name of the tool that replaces whole lines within a memory file.
  static const String replaceLinesToolName = 'file_memory_replace_lines';

  static const String descriptionSuffix = '_description.md';
  static const String memoryIndexFileName = 'memories.md';
  static const int maxIndexEntries = 50;

  static const String defaultInstructions = '''
## File Based Memory
You have access to a session-scoped, file-based memory system via the `file_memory_*` tools for storing and retrieving information across interactions.
These files act as your working memory for the current session and are isolated from other sessions.
Use these tools to store plans, memories, processing results, or downloaded data.

- Use descriptive file names (e.g., "projectarchitecture.md", "userpreferences.md").
- Include a description when writing a file to help with future discovery.
- Before starting new tasks, use file_memory_ls and file_memory_grep to check for relevant existing memories to avoid duplicate work.
- Keep memories up-to-date by overwriting files when information changes, or by using file_memory_replace and file_memory_replace_lines to make small edits.
- When you receive large amounts of data (e.g., downloaded web pages, API responses, research results),
  write them to files if they will be required later, so that they are not lost when older context is compacted or truncated.
  This ensures important data remains accessible across long-running sessions.
''';

  late final AgentFileStore _fileStore;
  late final ProviderSessionState<FileMemoryState> _sessionState;
  final Pool _writeLock = Pool(1);
  late final String _instructions;
  List<String>? _stateKeys;
  List<AITool>? _tools;

  @override
  List<String> get stateKeys => _stateKeys ??= [_sessionState.stateKey];

  /// Releases the resources used by the [FileMemoryProvider].
  @override
  void dispose() {
    unawaited(_writeLock.close());
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
          'The following is your memory index — a list of files you have '
          'previously written. You can read any of these files using the '
          'file_memory_read tool.\n\n'
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

    return _writeLock.withResource(() async {
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
    });
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

    return _writeLock.withResource(() async {
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
    });
  }

  /// Replace occurrences of a string in a memory file. Fails when the target
  /// string is absent, or when it is ambiguous and [replaceAll] is `false`.
  Future<String> replaceAsync(
    String fileName,
    String oldString,
    String newString, {
    bool replaceAll = false,
    CancellationToken? cancellationToken,
  }) async {
    final normalized = StorePaths.normalizeRelativePath(fileName);
    _validateMemoryFileName(normalized, fileName);

    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final path = combinePaths(state.workingFolder, normalized);

    return _writeLock.withResource(() async {
      final content = await _fileStore.readFileAsync(path, cancellationToken);
      if (content == null) {
        return "File '$fileName' not found.";
      }

      final (newContent, count) = FileEditor.applyReplace(
        content,
        oldString,
        newString,
        replaceAll: replaceAll,
      );
      await _fileStore.writeFileAsync(path, newContent, cancellationToken);
      return "Replaced $count occurrence(s) in '$fileName'.";
    });
  }

  /// Replace lines in a memory file. Each edit targets a 1-based line number
  /// with literal replacement text; an empty replacement deletes the line.
  Future<String> replaceLinesAsync(
    String fileName,
    List<FileLineEdit> edits, {
    CancellationToken? cancellationToken,
  }) async {
    final normalized = StorePaths.normalizeRelativePath(fileName);
    _validateMemoryFileName(normalized, fileName);

    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final path = combinePaths(state.workingFolder, normalized);

    return _writeLock.withResource(() async {
      final content = await _fileStore.readFileAsync(path, cancellationToken);
      if (content == null) {
        return "File '$fileName' not found.";
      }

      final newContent = FileEditor.applyReplaceLines(content, edits);
      await _fileStore.writeFileAsync(path, newContent, cancellationToken);
      return "Replaced ${edits.length} line(s) in '$fileName'.";
    });
  }

  /// List all memory files with their descriptions (if available).
  /// Description files are not shown separately. Optionally filter file
  /// names with a [globPattern].
  Future<List<FileListEntry>> listFilesAsync({
    String? globPattern,
    CancellationToken? cancellationToken,
  }) async {
    final state = _sessionState.getOrInitializeState(
      AIAgent.currentRunContext?.session,
    );
    final matcher = globPattern == null || globPattern.trim().isEmpty
        ? null
        : StorePaths.createGlobMatcher(globPattern);
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

      if (!StorePaths.matchesGlob(file, matcher)) {
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
      false,
      cancellationToken,
    );

    return results.where((r) => !isInternalFile(r.fileName)).toList();
  }

  List<AITool> createTools() {
    return [
      AIFunctionFactory.create(
        name: writeToolName,
        description:
            'Write a memory file with the given name and content. Overwrites the file if it already exists. Include a description for large files to provide a summary that helps with discovery.',
        parametersSchema: _objectSchema(
          {
            'fileName': 'The name of the file to write.',
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
        name: readFileToolName,
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
        name: deleteFileToolName,
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
        name: lsToolName,
        description:
            'List all memory files with their descriptions (if available). Optionally filter file names with a globPattern (e.g. "*.md"). Internal files (description sidecars and the memory index) are not shown.',
        parametersSchema: _objectSchema({
          'globPattern':
              'An optional glob pattern matched against file names to filter the listing.',
        }, required: const []),
        callback: (arguments, {cancellationToken}) {
          return listFilesAsync(
            globPattern: _getOptionalString(arguments, 'globPattern'),
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: grepToolName,
        description:
            'Search memory file contents using a regular expression pattern (case-insensitive). Optionally filter which files to search using a globPattern (e.g., "*.md", "research*"). Returns matching file names, content snippets, and matching lines with line numbers.',
        parametersSchema: _objectSchema(
          {
            'regexPattern':
                'A regular expression pattern to match against file contents.',
            'globPattern':
                'An optional glob pattern to filter which files are searched.',
          },
          required: ['regexPattern'],
        ),
        callback: (arguments, {cancellationToken}) {
          return searchFilesAsync(
            _getRequiredString(arguments, 'regexPattern'),
            filePattern: _getOptionalString(arguments, 'globPattern'),
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: replaceToolName,
        description:
            'Replace occurrences of oldString with newString in a memory file. Fails if oldString is not found, or if it occurs more than once and replaceAll is false. Returns the number of occurrences replaced.',
        parametersSchema: _objectSchema(
          {
            'fileName': 'The name of the file to modify.',
            'oldString': 'The substring to find and replace.',
            'newString': 'The replacement text.',
            'replaceAll':
                'When true, replace every occurrence; otherwise fail unless exactly one occurrence exists.',
          },
          required: ['fileName', 'oldString', 'newString'],
        ),
        callback: (arguments, {cancellationToken}) {
          return replaceAsync(
            _getRequiredString(arguments, 'fileName'),
            _getRequiredString(arguments, 'oldString'),
            _getRequiredString(arguments, 'newString'),
            replaceAll: _getOptionalBool(arguments, 'replaceAll') ?? false,
            cancellationToken: cancellationToken,
          );
        },
      ),
      AIFunctionFactory.create(
        name: replaceLinesToolName,
        description:
            'Replace lines in a memory file. Provide a list of edits, each with a 1-based line_number and a literal new_line (include your own trailing newline); an empty new_line deletes the line, including its line break. Fails on out-of-range or duplicate line numbers.',
        parametersSchema: const {
          'type': 'object',
          'properties': {
            'fileName': {'description': 'The name of the file to modify.'},
            'edits': {
              'type': 'array',
              'description':
                  'The list of 1-based line numbers and their literal replacement text.',
              'items': {
                'type': 'object',
                'properties': {
                  'line_number': {
                    'type': 'integer',
                    'description': '1-based line number to replace.',
                  },
                  'new_line': {
                    'type': 'string',
                    'description':
                        'Literal replacement text for the line; empty deletes the line.',
                  },
                },
                'required': ['line_number', 'new_line'],
              },
            },
          },
          'required': ['fileName', 'edits'],
        },
        callback: (arguments, {cancellationToken}) {
          return replaceLinesAsync(
            _getRequiredString(arguments, 'fileName'),
            _getLineEdits(arguments, 'edits'),
            cancellationToken: cancellationToken,
          );
        },
      ),
    ];
  }

  /// Throws when [normalized] refers to an internal system file (description
  /// sidecars and the memory index).
  static void _validateMemoryFileName(String normalized, String fileName) {
    if (isInternalFile(normalized)) {
      throw ArgumentError(
        'The provided file name is reserved by the system for internal use. '
            'Please choose a different file name.',
        'fileName',
      );
    }
  }

  static List<FileLineEdit> _getLineEdits(
    AIFunctionArguments arguments,
    String name,
  ) {
    final value = arguments[name];
    if (value is List) {
      return [
        for (final entry in value)
          if (entry is Map)
            FileLineEdit.fromJson(entry.cast<String, Object?>()),
      ];
    }
    throw ArgumentError.value(value, name, 'Expected a list of line edits.');
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
