import 'dart:async';

import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:pool/pool.dart';

import '../../../abstractions/ai_context.dart';
import '../../../abstractions/ai_context_provider.dart';
import '../file_store/agent_file_store.dart';
import '../file_store/file_editor.dart';
import '../file_store/file_line_edit.dart';
import '../file_store/file_search_result.dart';
import '../file_store/file_store_entry.dart';
import '../file_store/store_paths.dart';
import 'file_access_provider_options.dart';
import 'package:agents/src/abstractions/invoking_context.dart';

/// An [AIContextProvider] that provides file access tools to an agent for
/// writing, reading, deleting, listing, searching, and editing files.
///
/// The [FileAccessProvider] gives agents the ability to work with files in a
/// folder that the user has granted access to. Unlike `FileMemoryProvider`,
/// which provides session-scoped memory that may be isolated per session,
/// [FileAccessProvider] operates on a shared, persistent folder whose
/// contents are visible across sessions and agents. This makes it suitable
/// for reading input data, writing output artifacts, and working with files
/// that have a lifetime beyond any single agent session.
///
/// This provider exposes `file_access_write`, `file_access_read`,
/// `file_access_delete`, `file_access_ls`, `file_access_grep`,
/// `file_access_replace`, and `file_access_replace_lines`. When
/// [FileAccessProviderOptions.disableWriteTools] is set, only the read-only
/// tools (read, ls, and grep) are exposed.
///
/// By default, all of these tools require approval: each is exposed as an
/// [ApprovalRequiredAIFunction]. Approval can be disabled per group via
/// [FileAccessProviderOptions.disableReadOnlyToolApproval] (read, ls, and
/// grep) and [FileAccessProviderOptions.disableWriteToolApproval] (write,
/// delete, replace, and replace_lines). To auto-approve without prompting,
/// add [readOnlyToolsAutoApprovalRule] or [allToolsAutoApprovalRule] to
/// `ToolApprovalAgentOptions.autoApprovalRules`.
class FileAccessProvider extends AIContextProvider implements Disposable {
  /// Creates a [FileAccessProvider] using [fileStore] and optional [options].
  FileAccessProvider(
    AgentFileStore? fileStore, {
    FileAccessProviderOptions? options,
  }) {
    if (fileStore == null) {
      throw ArgumentError.notNull('fileStore');
    }

    _fileStore = fileStore;
    _instructions = options?.instructions ?? defaultInstructions;
    _disableWriteTools = options?.disableWriteTools ?? false;
    _disableReadOnlyToolApproval =
        options?.disableReadOnlyToolApproval ?? false;
    _disableWriteToolApproval = options?.disableWriteToolApproval ?? false;
  }

  /// The name of the tool that writes a file.
  static const String writeToolName = 'file_access_write';

  /// The name of the tool that reads a file.
  static const String readFileToolName = 'file_access_read';

  /// The name of the tool that deletes a file.
  static const String deleteFileToolName = 'file_access_delete';

  /// The name of the tool that lists the files and subdirectories in a
  /// directory.
  static const String lsToolName = 'file_access_ls';

  /// The name of the tool that searches file contents.
  static const String grepToolName = 'file_access_grep';

  /// The name of the tool that replaces occurrences of a substring within a
  /// file.
  static const String replaceToolName = 'file_access_replace';

  /// The name of the tool that replaces whole lines within a file.
  static const String replaceLinesToolName = 'file_access_replace_lines';

  /// The names of the tools that only read from (never modify) the store.
  static const Set<String> _readOnlyToolNames = {
    readFileToolName,
    lsToolName,
    grepToolName,
  };

  /// The names of all tools exposed by this provider.
  static const Set<String> _allToolNames = {
    writeToolName,
    readFileToolName,
    deleteFileToolName,
    lsToolName,
    grepToolName,
    replaceToolName,
    replaceLinesToolName,
  };

  /// An auto-approval rule that approves the read-only file access tools
  /// ([readFileToolName], [lsToolName], and [grepToolName]) while still
  /// prompting for tools that modify the store.
  static Future<bool> Function(FunctionCallContent functionCall)
  get readOnlyToolsAutoApprovalRule => _readOnlyToolsAutoApprovalRule;

  /// An auto-approval rule that approves all file access tools, including
  /// the tools that modify the file store.
  static Future<bool> Function(FunctionCallContent functionCall)
  get allToolsAutoApprovalRule => _allToolsAutoApprovalRule;

  static Future<bool> _readOnlyToolsAutoApprovalRule(
    FunctionCallContent functionCall,
  ) async => _readOnlyToolNames.contains(functionCall.name);

  static Future<bool> _allToolsAutoApprovalRule(
    FunctionCallContent functionCall,
  ) async => _allToolNames.contains(functionCall.name);

  /// The default instructions provided to the agent.
  static const String defaultInstructions = '''
## File Access
You have access to a shared file storage area via the `file_access_*` tools for reading, writing, and managing files.
These files persist beyond the current session and may be shared across sessions or agents.
Use these tools to read input data provided by the user, write output artifacts, and manage any files the user has asked you to work with.

- Never delete or overwrite existing files unless the user has explicitly asked you to do so.
- Files may be organized into subdirectories. Use `file_access_ls` to explore the tree level by level,
  or `file_access_grep` to search file contents recursively across the whole store.
- To make small edits to an existing file, prefer `file_access_replace` (substring replacement) or
  `file_access_replace_lines` (whole-line replacement) over rewriting the whole file.
''';

  late final AgentFileStore _fileStore;
  late final String _instructions;
  late final bool _disableWriteTools;
  late final bool _disableReadOnlyToolApproval;
  late final bool _disableWriteToolApproval;
  final Pool _writeLock = Pool(1);
  List<AITool>? _tools;

  @override
  List<String> get stateKeys => const [];

  @override
  void dispose() {
    unawaited(_writeLock.close());
  }

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

  /// Write a file with the given name and content. By default, does not
  /// overwrite an existing file unless [overwrite] is set to true.
  Future<String> writeFileAsync(
    String fileName,
    String content, {
    bool overwrite = false,
    CancellationToken? cancellationToken,
  }) async {
    final path = StorePaths.normalizeRelativePath(fileName);

    return _writeLock.withResource(() async {
      if (!overwrite &&
          await _fileStore.fileExistsAsync(path, cancellationToken)) {
        return "File '$fileName' already exists. To replace it, write again "
            'with overwrite set to true.';
      }

      await _fileStore.writeFileAsync(path, content, cancellationToken);
      return "File '$fileName' written.";
    });
  }

  /// Read the content of a file by name. Returns the file content or a
  /// message indicating the file was not found.
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

    return _writeLock.withResource(() async {
      final deleted = await _fileStore.deleteFileAsync(path, cancellationToken);
      return deleted
          ? "File '$fileName' deleted."
          : "File '$fileName' not found.";
    });
  }

  /// List the direct child files and subdirectories of a directory. Omit
  /// [directory] (or pass an empty string) to list the store root.
  /// Optionally filter entries with a [globPattern].
  Future<List<FileStoreEntry>> lsAsync({
    String? directory,
    String? globPattern,
    CancellationToken? cancellationToken,
  }) async {
    final target = directory == null || directory.trim().isEmpty
        ? ''
        : directory;
    final entries = await _fileStore.listChildrenAsync(
      target,
      cancellationToken,
    );

    final matcher = globPattern == null || globPattern.trim().isEmpty
        ? null
        : StorePaths.createGlobMatcher(globPattern);
    return [
      for (final entry in entries)
        if (StorePaths.matchesGlob(entry.name, matcher)) entry,
    ];
  }

  /// Replace occurrences of a string in a file. Fails when the target string
  /// is absent, or when it is ambiguous and [replaceAll] is `false`.
  Future<String> replaceAsync(
    String fileName,
    String oldString,
    String newString, {
    bool replaceAll = false,
    CancellationToken? cancellationToken,
  }) async {
    return _writeLock.withResource(() async {
      final path = StorePaths.normalizeRelativePath(fileName);
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

  /// Replace lines in a file. Each edit targets a 1-based line number with
  /// literal replacement text; an empty replacement deletes the line.
  Future<String> replaceLinesAsync(
    String fileName,
    List<FileLineEdit> edits, {
    CancellationToken? cancellationToken,
  }) async {
    return _writeLock.withResource(() async {
      final path = StorePaths.normalizeRelativePath(fileName);
      final content = await _fileStore.readFileAsync(path, cancellationToken);
      if (content == null) {
        return "File '$fileName' not found.";
      }

      final newContent = FileEditor.applyReplaceLines(content, edits);
      await _fileStore.writeFileAsync(path, newContent, cancellationToken);
      return "Replaced ${edits.length} line(s) in '$fileName'.";
    });
  }

  /// Search the contents of files in the store (recursively) using a regular
  /// expression pattern (case-insensitive). Optionally restrict to a base
  /// [directory] and/or filter which files to search using a [globPattern]
  /// matched against each file's path relative to the search directory.
  ///
  /// Result file names are paths relative to the store root, so they compose
  /// directly with the read/replace/delete tools.
  Future<List<FileSearchResult>> grepAsync(
    String regexPattern, {
    String? globPattern,
    String? directory,
    CancellationToken? cancellationToken,
  }) async {
    final pattern = globPattern == null || globPattern.trim().isEmpty
        ? null
        : globPattern;
    final target = StorePaths.normalizeRelativePath(
      directory ?? '',
      isDirectory: true,
    );
    final results = await _fileStore.searchFilesAsync(
      target,
      regexPattern,
      pattern,
      true,
      cancellationToken,
    );

    // The store returns file names relative to the searched directory;
    // re-root each result to the store root so the names compose directly
    // with file_access_read/replace/delete.
    if (target.isEmpty) {
      return results.toList();
    }

    return [
      for (final result in results)
        FileSearchResult()
          ..fileName = '$target/${result.fileName}'
          ..snippet = result.snippet
          ..matchingLines = result.matchingLines,
    ];
  }

  List<AITool> createTools() {
    // Read-only and store-modifying tools require approval by default.
    // Approval can be disabled per group via the provider options; otherwise
    // callers can use readOnlyToolsAutoApprovalRule or
    // allToolsAutoApprovalRule with the ToolApprovalAgent.
    final readOnlyRequiresApproval = !_disableReadOnlyToolApproval;
    final writeRequiresApproval = !_disableWriteToolApproval;

    final tools = <AITool>[
      _wrapWithApprovalIfRequired(
        AIFunctionFactory.create(
          name: readFileToolName,
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
        readOnlyRequiresApproval,
      ),
      _wrapWithApprovalIfRequired(
        AIFunctionFactory.create(
          name: lsToolName,
          description:
              'List the direct child files and subdirectories of a directory. Omit the directory (or pass an empty string) to list the root. To enumerate a subdirectory, pass its relative path, for example "reports" or "reports/2024". Optionally filter entries with a globPattern (e.g. "*.md"). Subdirectories are listed before files, and each entry has a name and a type of "file" or "directory".',
          parametersSchema: _objectSchema({
            'directory':
                'The relative directory path to list. Omit or pass an empty string to list the store root.',
            'globPattern':
                'An optional glob pattern (e.g., "*.md") matched against entry names to filter the listing.',
          }, required: const []),
          callback: (arguments, {cancellationToken}) {
            return lsAsync(
              directory: _getOptionalString(arguments, 'directory'),
              globPattern: _getOptionalString(arguments, 'globPattern'),
              cancellationToken: cancellationToken,
            );
          },
        ),
        readOnlyRequiresApproval,
      ),
      _wrapWithApprovalIfRequired(
        AIFunctionFactory.create(
          name: grepToolName,
          description:
              'Search the contents of files in the store (recursively, across all subdirectories) using a regular expression pattern (case-insensitive). Optionally restrict the search to a base directory (relative path), and filter which files to search using a glob pattern matched against each file\'s path relative to that directory: "*" matches within a single path segment; "**" matches across subdirectories, so use "**/*.md" to match markdown files at any depth, or "reports/**" to restrict the search to the "reports" subtree. Returns matching results whose file names are paths relative to the store root (usable with file_access_read), along with snippets and matching lines with line numbers.',
          parametersSchema: _objectSchema(
            {
              'regexPattern':
                  'A regular expression pattern to match against file contents (case-insensitive).',
              'globPattern':
                  'An optional glob pattern to filter which files to search, matched against each file\'s path relative to the search directory.',
              'directory':
                  'An optional base directory (relative path) to restrict the search to. Leave empty or omit to search the whole store.',
            },
            required: ['regexPattern'],
          ),
          callback: (arguments, {cancellationToken}) {
            return grepAsync(
              _getRequiredString(arguments, 'regexPattern'),
              globPattern: _getOptionalString(arguments, 'globPattern'),
              directory: _getOptionalString(arguments, 'directory'),
              cancellationToken: cancellationToken,
            );
          },
        ),
        readOnlyRequiresApproval,
      ),
    ];

    if (!_disableWriteTools) {
      tools.addAll([
        _wrapWithApprovalIfRequired(
          AIFunctionFactory.create(
            name: writeToolName,
            description:
                'Write a file with the given name and content. By default, does not overwrite an existing file unless overwrite is set to true.',
            parametersSchema: _objectSchema(
              {
                'fileName': 'The name of the file to write.',
                'content': 'The content to write to the file.',
                'overwrite':
                    'Whether to overwrite the file if it already exists.',
              },
              required: ['fileName', 'content'],
            ),
            callback: (arguments, {cancellationToken}) {
              return writeFileAsync(
                _getRequiredString(arguments, 'fileName'),
                _getRequiredString(arguments, 'content'),
                overwrite: _getOptionalBool(arguments, 'overwrite') ?? false,
                cancellationToken: cancellationToken,
              );
            },
          ),
          writeRequiresApproval,
        ),
        _wrapWithApprovalIfRequired(
          AIFunctionFactory.create(
            name: deleteFileToolName,
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
          writeRequiresApproval,
        ),
        _wrapWithApprovalIfRequired(
          AIFunctionFactory.create(
            name: replaceToolName,
            description:
                'Replace occurrences of oldString with newString in a file. Fails if oldString is not found, or if it occurs more than once and replaceAll is false. Returns the number of occurrences replaced.',
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
          writeRequiresApproval,
        ),
        _wrapWithApprovalIfRequired(
          AIFunctionFactory.create(
            name: replaceLinesToolName,
            description:
                'Replace lines in a file. Provide a list of edits, each with a 1-based line_number and a literal new_line (include your own trailing newline); an empty new_line deletes the line, including its line break. Fails on out-of-range or duplicate line numbers.',
            parametersSchema: lineEditsSchema,
            callback: (arguments, {cancellationToken}) {
              return replaceLinesAsync(
                _getRequiredString(arguments, 'fileName'),
                _getLineEdits(arguments, 'edits'),
                cancellationToken: cancellationToken,
              );
            },
          ),
          writeRequiresApproval,
        ),
      ]);
    }

    return tools;
  }

  /// The parameters schema shared by the replace_lines tools.
  static const Map<String, dynamic> lineEditsSchema = {
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
  };

  static AITool _wrapWithApprovalIfRequired(
    AIFunction function,
    bool requireApproval,
  ) => requireApproval ? ApprovalRequiredAIFunction(function) : function;

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
