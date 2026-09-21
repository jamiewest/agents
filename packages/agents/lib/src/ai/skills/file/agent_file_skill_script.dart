import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import '../../../json_stubs.dart';
import '../agent_skill.dart';
import '../agent_skill_script.dart';
import 'agent_file_skill.dart';
import 'agent_file_skill_path_scope.dart';
import 'agent_file_skill_path_validator.dart';
import 'agent_file_skill_script_runner.dart';

/// A file-path-backed skill script.
class AgentFileSkillScript extends AgentSkillScript {
  /// Creates an [AgentFileSkillScript] with the given [name] and [fullPath].
  ///
  /// [scope] is the trusted path scope the script was discovered in. When
  /// supplied, the file is revalidated against it immediately before the
  /// script runs, so a path swapped for a link after discovery is rejected.
  AgentFileSkillScript(
    super.name,
    this.fullPath, {
    AgentFileSkillScriptRunner? runner,
    AgentFileSkillPathScope? scope,
    FileSystem fs = const LocalFileSystem(),
  }) : _runner = runner,
       _scope = scope,
       _fs = fs;

  static const JsonElement defaultSchema = JsonElement({
    'type': 'array',
    'items': {'type': 'string'},
  });

  final AgentFileSkillScriptRunner? _runner;
  final AgentFileSkillPathScope? _scope;
  final FileSystem _fs;
  final String fullPath;

  @override
  JsonElement? get parametersSchema => defaultSchema;

  @override
  Future<Object?> run(
    AgentSkill skill,
    JsonElement? arguments,
    ServiceProvider? serviceProvider, {
    CancellationToken? cancellationToken,
  }) async {
    if (skill is! AgentFileSkill) {
      throw StateError(
        'File-based script $name requires an AgentFileSkill but received ${skill.runtimeType}.',
      );
    }
    final runner = _runner;
    if (runner == null) {
      throw StateError(
        'Script $name cannot be executed because no AgentFileSkillScriptRunner was provided.',
      );
    }
    final scope = _scope;
    if (scope != null) {
      AgentFileSkillPathValidator.validateForUse(
        fullPath,
        scope,
        'Script',
        name,
        fs: _fs,
      );
    }

    return runner(
      skill,
      this,
      arguments,
      serviceProvider,
      cancellationToken: cancellationToken,
    );
  }
}
