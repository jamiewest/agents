import 'dart:io';
import 'package:extensions/system.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../agent_json_utilities.dart';
import '../file_memory/file_memory_provider.dart';
import '../file_store/agent_file_store.dart';
import '../file_store/file_search_result.dart';
import '../file_store/store_paths.dart';
import 'file_access_provider_options.dart';

/// An [AIContextProvider] that provides file access tools to an agent for
/// saving, reading, deleting, listing, and searching files.
///
/// Remarks: The [FileAccessProvider] gives agents the ability to work with
/// files in a folder that the user has granted access to. Unlike
/// [FileMemoryProvider], which provides session-scoped memory that may be
/// isolated per session, [FileAccessProvider] operates on a shared,
/// persistent folder whose contents are visible across sessions and agents.
/// This makes it suitable for reading input data, writing output artifacts,
/// and working with files that have a lifetime beyond any single agent
/// session. File access is mediated through a [AgentFileStore] abstraction,
/// allowing pluggable backends (in-memory, local file system, remote blob
/// storage, etc.). This provider exposes the following tools to the agent:
/// `SaveFile` — Save a file with the given name and content. `ReadFile` —
/// Read the content of a file by name. `DeleteFile` — Delete a file by name.
/// `ListFiles` — List all file names. `SearchFiles` — Search file contents
/// using a regular expression pattern.
class FileAccessProvider extends AIContextProvider {
  /// Initializes a new instance of the [FileAccessProvider] class.
  ///
  /// [fileStore] The file store implementation used for storage operations. The
  /// store should already be scoped to the desired folder or storage location.
  ///
  /// [options] Optional settings that control provider behavior. When `null`,
  /// defaults are used.
  FileAccessProvider(
    AgentFileStore fileStore,
    {FileAccessProviderOptions? options = null, },
  ) : _fileStore = fileStore {
    this._instructions = options?.instructions ?? DefaultInstructions;
  }

  final AgentFileStore _fileStore;

  late final String _instructions;

  List<AITool>? _tools;

  List<String> get stateKeys {
    return [];
  }

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) {
    return Future<AIContext>(AIContext());
  }

  /// Save a file with the given name and content. By default, does not
  /// overwrite an existing file unless overwrite is set to true.
  ///
  /// Returns: A confirmation message.
  ///
  /// [fileName] The name of the file to save.
  ///
  /// [content] The content to write to the file.
  ///
  /// [overwrite] Whether to overwrite the file if it already exists.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String> saveFile(
    String fileName,
    String content,
    {bool? overwrite, CancellationToken? cancellationToken, },
  ) async  {
    var path = StorePaths.normalizeRelativePath(fileName);
    if (!overwrite && await this._fileStore.fileExistsAsync(path, cancellationToken)) {
      return "File ${fileName} already exists. To replace it, save again with overwrite set to true.";
    }
    await this._fileStore.writeFileAsync(path, content, cancellationToken);
    return "File ${fileName} saved.";
  }

  /// Read the content of a file by name. Returns the file content or a message
  /// indicating the file was not found.
  ///
  /// Returns: The file content or a not-found message.
  ///
  /// [fileName] The name of the file to read.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String> readFile(String fileName, {CancellationToken? cancellationToken, }) async  {
    var path = StorePaths.normalizeRelativePath(fileName);
    var content = await this._fileStore.readFileAsync(
      path,
      cancellationToken,
    ) ;
    return content ?? "File ${fileName} not found.";
  }

  /// Delete a file by name.
  ///
  /// Returns: A confirmation or not-found message.
  ///
  /// [fileName] The name of the file to delete.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<String> deleteFile(String fileName, {CancellationToken? cancellationToken, }) async  {
    var path = StorePaths.normalizeRelativePath(fileName);
    var deleted = await this._fileStore.deleteFileAsync(
      path,
      cancellationToken,
    ) ;
    return deleted ? "File ${fileName} deleted." : "File ${fileName} not found.";
  }

  /// List all file names.
  ///
  /// Returns: A list of file names.
  ///
  /// [cancellationToken] A token to cancel the operation.
  Future<List<String>> listFiles({CancellationToken? cancellationToken}) async  {
    var fileNames = await this._fileStore.listFilesAsync(
      '',
      cancellationToken,
    ) ;
    return List<String>(fileNames);
  }

  /// Search file contents using a regular expression pattern
  /// (case-insensitive). Optionally filter which files to search using a glob
  /// pattern.
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
    var pattern = (filePattern == null || filePattern.trim().isEmpty) ? null : filePattern;
    var results = await this._fileStore.searchFilesAsync(
      '',
      regexPattern,
      pattern,
      cancellationToken,
    ) ;
    return List<FileSearchResult>(results);
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
}
