import 'dart:io';

import 'package:path/path.dart' as p;

import 'checkpoint.dart';
import 'checkpoint_store.dart';
import 'json_marshaller.dart';

/// File-system JSON checkpoint store.
class FileSystemJsonCheckpointStore implements CheckpointStore {
  /// Creates a file-system JSON checkpoint store rooted at [rootDirectory].
  FileSystemJsonCheckpointStore(
    String rootDirectory, {
    JsonMarshaller jsonMarshaller = const JsonMarshaller(),
  }) : _rootDirectory = Directory(rootDirectory),
       _jsonMarshaller = jsonMarshaller {
    if (rootDirectory.trim().isEmpty) {
      throw ArgumentError.value(rootDirectory, 'rootDirectory');
    }
    _rootDirectory.createSync(recursive: true);
  }

  final Directory _rootDirectory;
  final JsonMarshaller _jsonMarshaller;

  /// Gets the canonical root directory path.
  String get rootDirectory => _rootDirectory.absolute.path;

  @override
  Future<void> writeCheckpointAsync(Checkpoint checkpoint) async {
    final file = _fileFor(checkpoint.info.checkpointId);
    await file.parent.create(recursive: true);
    await file.writeAsString(_jsonMarshaller.serialize(checkpoint.toJson()));
  }

  @override
  Future<Checkpoint?> readCheckpointAsync(String checkpointId) async {
    final file = _fileFor(checkpointId);
    if (!await file.exists()) {
      return null;
    }
    final json = _jsonMarshaller.deserialize(await file.readAsString())! as Map;
    return Checkpoint.fromJson(json.cast<String, Object?>());
  }

  @override
  Future<List<Checkpoint>> listCheckpointsAsync({String? sessionId}) async {
    if (!await _rootDirectory.exists()) {
      return <Checkpoint>[];
    }
    final checkpoints = <Checkpoint>[];
    await for (final entity in _rootDirectory.list()) {
      if (entity is! File || p.extension(entity.path) != '.json') {
        continue;
      }
      final checkpointId = p.basenameWithoutExtension(entity.path);
      final checkpoint = await readCheckpointAsync(checkpointId);
      if (checkpoint == null) {
        continue;
      }
      if (sessionId == null || checkpoint.sessionId == sessionId) {
        checkpoints.add(checkpoint);
      }
    }
    checkpoints.sort(
      (left, right) =>
          left.info.checkpointId.compareTo(right.info.checkpointId),
    );
    return checkpoints;
  }

  @override
  Future<bool> deleteCheckpointAsync(String checkpointId) async {
    final file = _fileFor(checkpointId);
    if (!await file.exists()) {
      return false;
    }
    await file.delete();
    return true;
  }

  File _fileFor(String checkpointId) {
    final safeId = _normalizeCheckpointId(checkpointId);
    final candidate = File(p.join(_rootDirectory.path, '$safeId.json'));
    final root = p.canonicalize(_rootDirectory.absolute.path);
    final candidatePath = p.canonicalize(candidate.absolute.path);
    if (!p.isWithin(root, candidatePath) && candidatePath != root) {
      throw ArgumentError.value(checkpointId, 'checkpointId');
    }
    return candidate;
  }

  static String _normalizeCheckpointId(String checkpointId) {
    if (checkpointId.trim().isEmpty ||
        checkpointId.contains('/') ||
        checkpointId.contains(r'\') ||
        checkpointId.contains('..') ||
        p.isAbsolute(checkpointId)) {
      throw ArgumentError.value(checkpointId, 'checkpointId');
    }
    return checkpointId;
  }
}
