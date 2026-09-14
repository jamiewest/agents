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
  /// Creates an [AgentFileSkillResource] with the given [name] and
  /// [fullPath], discovered within [scope].
  AgentFileSkillResource(
    super.name,
    this.fullPath,
    this._scope, {
    FileSystem fs = const LocalFileSystem(),
  }) : _fs = fs;

  /// Gets the absolute file path to the resource.
  final String fullPath;
  final AgentFileSkillPathScope _scope;
  final FileSystem _fs;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    final validatedPath = AgentFileSkillPathValidator.validateForUse(
      fullPath,
      _scope,
      'Resource',
      name,
      fs: _fs,
    );
    return await _fs.file(validatedPath).readAsString();
  }
}
