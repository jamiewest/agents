import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import '../agent_skill_resource.dart';

/// A file-path-backed skill resource. Reads content from a file on disk
/// relative to the skill directory.
class AgentFileSkillResource extends AgentSkillResource {
  /// Creates an [AgentFileSkillResource] with the given [name] and [fullPath].
  AgentFileSkillResource(
    super.name,
    this.fullPath, {
    FileSystem fs = const LocalFileSystem(),
  }) : _fs = fs;

  /// Gets the absolute file path to the resource.
  final String fullPath;
  final FileSystem _fs;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    return await _fs.file(fullPath).readAsString();
  }
}
