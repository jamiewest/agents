import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import '../agent_skill_resource.dart';
import 'agent_file_skill_path_scope.dart';
import 'agent_file_skill_path_validator.dart';

/// A file-path-backed skill resource. Reads content from a file on disk
/// relative to the skill directory.
class AgentFileSkillResource extends AgentSkillResource {
  /// Creates an [AgentFileSkillResource] with the given [name] and [fullPath].
  ///
  /// [scope] is the trusted path scope the resource was discovered in. When
  /// supplied, the file is revalidated against it immediately before it is
  /// read, so a path swapped for a link after discovery is rejected.
  AgentFileSkillResource(
    super.name,
    this.fullPath, {
    FileSystem fs = const LocalFileSystem(),
    AgentFileSkillPathScope? scope,
  }) : _fs = fs,
       _scope = scope;

  /// Gets the absolute file path to the resource.
  final String fullPath;
  final FileSystem _fs;
  final AgentFileSkillPathScope? _scope;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    final scope = _scope;
    final validatedPath = scope == null
        ? fullPath
        : AgentFileSkillPathValidator.validateForUse(
            fullPath,
            scope,
            'Resource',
            name,
            fs: _fs,
          );
    return await _fs.file(validatedPath).readAsString();
  }
}
