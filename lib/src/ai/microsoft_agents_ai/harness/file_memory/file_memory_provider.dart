import 'dart:io';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../../../func_typedefs.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../../agent_json_utilities.dart';
import '../file_store/agent_file_store.dart';
import '../file_store/file_search_result.dart';
import '../file_store/store_paths.dart';
import 'file_list_entry.dart';
import 'file_memory_provider_options.dart';
import 'file_memory_state.dart';
import '../../../../semaphore_slim.dart';

/// An [AIContextProvider] that provides file-based memory tools to an agent
/// for storing, retrieving, modifying, listing, deleting, and searching
/// files.
///
/// Remarks: The [FileMemoryProvider] enables agents to persist information
/// across interactions using a file-based storage model. Each memory is
/// stored as an individual file with a meaningful name. For large files, a
/// companion description file (suffixed with `_description.md`) can be stored
/// alongside the main file to provide a summary. File access is mediated
/// through a [AgentFileStore] abstraction, allowing pluggable backends
/// (in-memory, local file system, remote blob storage, etc.). This provider
/// exposes the following tools to the agent: `SaveFile` — Save a memory file
/// with the given name, content, and an optional description. `ReadFile` —
/// Read the content of a file by name. `DeleteFile` — Delete a file by name.
/// `ListFiles` — List all files with their descriptions (if available).
/// `SearchFiles` — Search file contents using a regular expression pattern.
class FileMemoryProvider extends AIContextProvider implements Disposable {
  /// Initializes a new instance of the [FileMemoryProvider] class.
  ///
  /// [fileStore] The file store implementation used for storage operations.
  ///
  /// [stateInitializer] An optional function that initializes the
  /// [FileMemoryState] for a new session. Use this to customize the working
  /// folder (e.g., per-user or per-session subfolders). When `null`, the
  /// default initializer creates state with an empty working folder.
  ///
  /// [options] Optional settings that control provider behavior. When `null`,
  /// defaults are used.
  FileMemoryProvider(
    AgentFileStore fileStore,
    {Func<AgentSession?, FileMemoryState>? stateInitializer = null, FileMemoryProviderOptions? options = null, },
  ) : _fileStore = fileStore {
    this._instructions = options?.instructions ?? DefaultInstructions;
    this._sessionState = ProviderSessionState<FileMemoryState>(
            stateInitializer ?? ((_) => FileMemoryState()),
            this.runtimeType.toString(),
            AgentJsonUtilities.defaultOptions);
  }

  final AgentFileStore _fileStore;

  late final ProviderSessionState<FileMemoryState> _sessionState;

  final SemaphoreSlim _writeLock = SemaphoreSlim(1, 1);

  late final String _instructions;

  List<String>? _stateKeys;

  List<AITool>? _tools;

  List<String> get stateKeys {
    return this._stateKeys ??= [this._sessionState.stateKey];
  }

  /// Releases the resources used by the [FileMemoryProvider].
  @override
  void dispose() {
    this._writeLock.dispose();
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    var state = this._sessionState.getOrInitializeState(context.session);
    if (!(state.workingFolder == null || state.workingFolder.isEmpty)) {
      await this._fileStore.createDirectoryAsync(
        state.workingFolder,
        cancellationToken,
      ) ;
    }
    var aiContext = AIContext();
    var indexPath = combinePaths(state.workingFolder, MemoryIndexFileName);
    var indexContent = await this._fileStore.readFileAsync(
      indexPath,
      cancellationToken,
    ) ;
    if (!(indexContent == null || indexContent.trim().isEmpty)) {
      aiContext.messages =
            [
                ChatMessage.fromText(ChatRole.user, "The following is your memory index — a list of files you have previously saved. " +
                    "You can read any of these files using the FileMemory_ReadFile tool.\n\n" +
                    indexContent),
            ];
    }
    return aiContext;
  }

  /// Save a memory file with the given name and content. Overwrites the file if
  /// it already exists. Include a description for large files to provide a
  /// summary that helps with discovery.
  ///
  /// Returns: A confirmation message.
  ///
  /// [fileName] The name of the file to save.
  ///
  /// [content] The content to write to the file.
  ///
  /// [description] An optional description of the file contents for discovery.
  /// Leave empty or omit to skip.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String> saveFile(
    String fileName,
    String content,
    {String? description, CancellationToken? cancellationToken, },
  ) async  {
    if (isInternalFile(fileName)) {
      throw ArgumentError(
        "The provided file name is reserved by the system for internal use. Please choose a different file name.",
        'fileName',
      );
    }
    var state = this._sessionState.getOrInitializeState(AIAgent.currentRunContext?.session);
    var path = resolvePath(state.workingFolder, fileName);
    await this._writeLock.waitAsync(cancellationToken);
    try {
      await this._fileStore.writeFileAsync(path, content, cancellationToken);
      var descPath = resolvePath(state.workingFolder, getDescriptionFileName(fileName));
      if (!(description == null || description.trim().isEmpty)) {
        await this._fileStore.writeFileAsync(
          descPath,
          description,
          cancellationToken,
        ) ;
      } else {
        // Remove any stale description file when no description is provided.
                await this._fileStore.deleteFileAsync(
                  descPath,
                  cancellationToken,
                ) ;
      }
      var result = (description == null || description.trim().isEmpty)
                ? "File ${fileName} saved."
                : "File ${fileName} saved with description.";
      await this.rebuildMemoryIndexAsync(state, cancellationToken);
      return result;
    } finally {
      this._writeLock.release();
    }
  }

  /// Read the content of a memory file by name. Returns the file content or a
  /// message indicating the file was not found.
  ///
  /// Returns: The file content or a not-found message.
  ///
  /// [fileName] The name of the file to read.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String> readFile(String fileName, {CancellationToken? cancellationToken, }) async  {
    var state = this._sessionState.getOrInitializeState(AIAgent.currentRunContext?.session);
    var path = resolvePath(state.workingFolder, fileName);
    var content = await this._fileStore.readFileAsync(
      path,
      cancellationToken,
    ) ;
    return content ?? "File ${fileName} not found.";
  }

  /// Delete a memory file by name. Also removes its companion description file
  /// if one exists.
  ///
  /// Returns: A confirmation or not-found message.
  ///
  /// [fileName] The name of the file to delete.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String> deleteFile(String fileName, {CancellationToken? cancellationToken, }) async  {
    var state = this._sessionState.getOrInitializeState(AIAgent.currentRunContext?.session);
    var path = resolvePath(state.workingFolder, fileName);
    await this._writeLock.waitAsync(cancellationToken);
    try {
      var deleted = await this._fileStore.deleteFileAsync(
        path,
        cancellationToken,
      ) ;
      var descPath = resolvePath(state.workingFolder, getDescriptionFileName(fileName));
      await this._fileStore.deleteFileAsync(descPath, cancellationToken);
      await this.rebuildMemoryIndexAsync(state, cancellationToken);
      return deleted ? "File ${fileName} deleted." : "File ${fileName} not found.";
    } finally {
      this._writeLock.release();
    }
  }

  /// List all memory files with their descriptions (if available). Description
  /// files are not shown separately.
  ///
  /// Returns: A list of file entries with names and optional descriptions.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<List<FileListEntry>> listFiles({CancellationToken? cancellationToken}) async  {
    var state = this._sessionState.getOrInitializeState(AIAgent.currentRunContext?.session);
    var fileNames = await this._fileStore.listFilesAsync(
      state.workingFolder,
      cancellationToken,
    ) ;
    var descriptionFileSet = Set<String>();
    for (final file in fileNames) {
      if (file.endsWith(DescriptionSuffix)) {
        descriptionFileSet.add(file);
      }
    }
    var entries = List<FileListEntry>();
    for (final file in fileNames) {
      if (descriptionFileSet.contains(file)) {
        continue;
      }
      if (isInternalFile(file)) {
        continue;
      }
      var fileDescription = null;
      var descFileName = getDescriptionFileName(file);
      if (descriptionFileSet.contains(descFileName)) {
        var descPath = combinePaths(state.workingFolder, descFileName);
        fileDescription = await this._fileStore.readFileAsync(
          descPath,
          cancellationToken,
        ) ;
      }
      entries.add(FileListEntry());
    }
    return entries;
  }

  /// Search memory file contents using a regular expression pattern
  /// (case-insensitive). Optionally filter which files to search using a glob
  /// pattern. Returns matching file names, content snippets, and matching lines
  /// with line numbers.
  ///
  /// Returns: A list of search results with matching file names, snippets, and
  /// matching lines.
  ///
  /// [regexPattern] A regular expression pattern to match against file contents
  /// (case-insensitive).
  ///
  /// [filePattern] An optional glob pattern to filter which files to search
  /// (e.g., "*.md", "research*"). Leave empty or omit to search all files.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<List<FileSearchResult>> searchFiles(
    String regexPattern,
    {String? filePattern, CancellationToken? cancellationToken, },
  ) async  {
    var state = this._sessionState.getOrInitializeState(AIAgent.currentRunContext?.session);
    var pattern = (filePattern == null || filePattern.trim().isEmpty) ? null : filePattern;
    var results = await this._fileStore.searchFilesAsync(
      state.workingFolder,
      regexPattern,
      pattern,
      cancellationToken,
    ) ;
    var filtered = List<FileSearchResult>(results.length);
    for (final result in results) {
      if (isInternalFile(result.fileName)) {
        continue;
      }
      filtered.add(result);
    }
    return filtered;
  }

  List<AITool> createTools() {
    var serializerOptions = AgentJsonUtilities.defaultOptions;
    return [
            AIFunctionFactory.create(this.saveFileAsync, AIFunctionFactoryOptions()),
            AIFunctionFactory.create(this.readFileAsync, AIFunctionFactoryOptions()),
            AIFunctionFactory.create(this.deleteFileAsync, AIFunctionFactoryOptions()),
            AIFunctionFactory.create(this.listFilesAsync, AIFunctionFactoryOptions()),
            AIFunctionFactory.create(this.searchFilesAsync, AIFunctionFactoryOptions()),
        ];
  }

  /// Rebuilds the `memories.md` index file by listing all user files in the
  /// working folder, reading their companion description files, and writing a
  /// markdown summary capped at [MaxIndexEntries] entries.
  Future rebuildMemoryIndex(FileMemoryState state, CancellationToken cancellationToken, ) async  {
    var fileNames = await this._fileStore.listFilesAsync(
      state.workingFolder,
      cancellationToken,
    ) ;
    var sortedFiles = fileNames.orderBy((f) => f, ).toList();
    var sb = StringBuffer();
    sb.writeln("# Memory Index");
    sb.writeln();
    var count = 0;
    for (final file in sortedFiles) {
      if (isInternalFile(file)) {
        continue;
      }
      if (count >= MaxIndexEntries) {
        break;
      }
      var description = null;
      var descFileName = getDescriptionFileName(file);
      var descPath = combinePaths(state.workingFolder, descFileName);
      description = await this._fileStore.readFileAsync(
        descPath,
        cancellationToken,
      ) ;
      if (!(description == null || description.trim().isEmpty)) {
        sb.writeln('- **${file}**: ${description}');
      } else {
        sb.writeln('- **${file}**');
      }
      count++;
    }
    var indexPath = combinePaths(state.workingFolder, MemoryIndexFileName);
    await this._fileStore.writeFileAsync(
      indexPath,
      sb.toString(),
      cancellationToken,
    ) ;
  }

  static String getDescriptionFileName(String fileName) {
    var extIndex = fileName.lastIndexOf('.');
    if (extIndex > 0) {
      return fileName.substring(0, extIndex) + DescriptionSuffix;
    }
    return fileName + DescriptionSuffix;
  }

  /// Returns `true` if the file is an internal system file that should be
  /// hidden from user-facing operations (description sidecars and the memory
  /// index).
  static bool isInternalFile(String fileName) {
    return fileName.endsWith(DescriptionSuffix) ||
        fileName == MemoryIndexFileName;
  }

  static String resolvePath(String workingFolder, String fileName, ) {
    var normalizedFileName = StorePaths.normalizeRelativePath(fileName);
    var normalizedWorkingFolder = workingFolder.replaceAll('\\', '/');
    return combinePaths(normalizedWorkingFolder, normalizedFileName);
  }

  static String combinePaths(String basePath, String relativePath, ) {
    if ((basePath == null || basePath.isEmpty)) {
      return relativePath;
    }
    if ((relativePath == null || relativePath.isEmpty)) {
      return basePath;
    }
    return basePath.trimRight('/') + "/" + relativePath.trimLeft('/');
  }
}
