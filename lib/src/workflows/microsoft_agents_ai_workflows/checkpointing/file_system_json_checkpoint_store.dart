import 'dart:convert';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:extensions/system.dart';
import '../checkpoint_info.dart';
import '../workflows_json_utilities.dart';
import 'checkpoint.dart';
import 'json_checkpoint_store.dart';
import '../../../json_stubs.dart';

class CheckpointFileIndexEntry {
  const CheckpointFileIndexEntry(
    CheckpointInfo CheckpointInfo,
    String FileName,
  ) :
      checkpointInfo = CheckpointInfo,
      fileName = FileName;

  CheckpointInfo checkpointInfo;

  String fileName;

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is CheckpointFileIndexEntry &&
    checkpointInfo == other.checkpointInfo &&
    fileName == other.fileName; }
  @override
  int get hashCode { return Object.hash(checkpointInfo, fileName); }
}
/// Provides a file system-based implementation of a JSON checkpoint store
/// that persists checkpoint data and index information to disk using JSON
/// files.
///
/// Remarks: This class manages checkpoint storage by writing JSON files to a
/// specified directory and maintaining an index file for efficient retrieval.
/// It is intended for scenarios where durable, process-exclusive checkpoint
/// persistence is required. Instances of this class are not thread-safe and
/// should not be shared across multiple threads without external
/// synchronization. The class implements IDisposable; callers should ensure
/// Dispose is called to release file handles and system resources when the
/// store is no longer needed.
class FileSystemJsonCheckpointStore extends JsonCheckpointStore implements Disposable {
  /// Initializes a new instance of the [FileSystemJsonCheckpointStore] class
  /// that uses the specified directory
  ///
  /// [directory]
  FileSystemJsonCheckpointStore(DirectoryInfo directory) : directory = directory {
    this.directory = directory ?? throw ArgumentError.notNull('directory');
    if (!directory.exists) {
      directory.create();
    }
    try {
      this._indexFile = File.open(
        p.join(directory.fullName, "index.jsonl"),
        FileMode.openOrCreate,
        FileAccess.readWrite,
        FileShare.none,
      );
    } catch (e, s) {
      {
        throw StateError("The store at ${directory.fullName} is already in use by another process.");
      }
    }
    try {
      // read the lines of indexfile and parse them as CheckpointInfos
            this.checkpointIndex = [];
      var BufferSize = 1024;
      var reader = new(
        this._indexFile,
        encoding: const Utf8Codec(),
        detectEncodingFromByteOrderMarks: false,
        BufferSize,
        leaveOpen: true,
      );
      while (reader.readLine() is String) {
        if (JsonSerializer.deserialize(line, (entryTypeInfo)) != null) {
          // We never actually use the file names from the index entries since they can be derived from the CheckpointInfo, but it is useful to
                    // have the UrlEncoded file names in the index file for human readability
                    this.checkpointIndex.add(entry.checkpointInfo);
        }
      }
    } catch (e, s) {
      if (e is Exception) {
        final exception = e as Exception;
        {
          throw StateError(
            "Could not load store at ${directory.fullName}. Index corrupted.",
            exception,
          );
        }
      } else {
        rethrow;
      }
    }
  }

  late FileStream? _indexFile;

  final DirectoryInfo directory;

  late final Set<CheckpointInfo> checkpointIndex;

  static JsonTypeInfo<CheckpointFileIndexEntry> get entryTypeInfo {
    return WorkflowsJsonUtilities.jsonContext.defaultValue.checkpointFileIndexEntry;
  }

  @override
  void dispose() {
    var indexFileLocal = (() { final _old = this._indexFile; this._indexFile = null; return _old; })();
    indexFileLocal?.dispose();
  }

  void checkDisposed() {
    if (this._indexFile == null) {
      throw objectDisposedException('${'FileSystemJsonCheckpointStore'}(${this.directory.fullName})');
    }
  }

  String getFileNameForCheckpoint(String sessionId, CheckpointInfo key, ) {
    var protoPath = '${sessionId}_${key.checkpointId}.json';
    return Uri.escapeDataString(protoPath) // This takes care of most of the invalid path characters
                  .replaceAll(".", "%2E");
  }

  CheckpointInfo getUnusedCheckpointInfo(String sessionId) {
    CheckpointInfo key;
    do {
      key = new(sessionId);
    } while (!this.checkpointIndex.add(key));
    return key;
  }

  @override
  Future<CheckpointInfo> createCheckpoint(
    String sessionId,
    JsonElement value,
    {CheckpointInfo? parent, }
  ) async {
    this.checkDisposed();
    var key = this.getUnusedCheckpointInfo(sessionId);
    var fileName = this.getFileNameForCheckpoint(sessionId, key);
    var filePath = p.join(this.directory.fullName, fileName);
    try {
      var checkpointStream = File.open(filePath, FileMode.create, FileAccess.write, FileShare.none);
      var jsonWriter = new(checkpointStream, jsonWriterOptions());
      value.writeTo(jsonWriter);
      var entry = new(key, fileName);
      JsonSerializer.serialize(this._indexFile!, entry, entryTypeInfo);
      var bytes = utf8.encode(Environment.newLine);
      await this._indexFile!.writeAsync(
        bytes,
        0,
        bytes.length,
        CancellationToken.none,
      ) ;
      await this._indexFile!.flushAsync(CancellationToken.none);
      return key;
    } catch (e, s) {
      if (e is Exception) {
        final ex = e as Exception;
        {
          this.checkpointIndex.remove(key);
          try {
            // try to clean up after ourselves
                File.delete(filePath);
          } catch (e, s) {
            }
          }
          throw StateError(
            "Could not create checkpoint in store at ${this.directory.fullName}.",
            ex,
          );
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<JsonElement> retrieveCheckpoint(String sessionId, CheckpointInfo key, ) async {
    this.checkDisposed();
    var fileName = this.getFileNameForCheckpoint(sessionId, key);
    var filePath = p.join(this.directory.fullName, fileName);
    if (!this.checkpointIndex.contains(key) ||
            !File.exists(filePath)) {
      throw StateError('Checkpoint ${key.checkpointId} not found in store at "${this.directory.fullName}".');
    }
    var checkpointFileStream = File.open(filePath, FileMode.open, FileAccess.read, FileShare.read);
    var document = await JsonDocument.parseAsync(checkpointFileStream);
    return document.rootElement.clone();
  }

  @override
  Future<Iterable<CheckpointInfo>> retrieveIndex(String sessionId, {CheckpointInfo? withParent, }) {
    this.checkDisposed();
    return new(this.checkpointIndex);
  }
}
