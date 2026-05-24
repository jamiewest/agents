import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';

import '../../../json_stubs.dart';
import '../agent_skill.dart';
import '../agent_skill_script.dart';
import 'agent_file_skill.dart';
import 'agent_file_skill_script_runner.dart';

/// A file-path-backed skill script.
class AgentFileSkillScript extends AgentSkillScript {
  AgentFileSkillScript(
    super.name,
    this.fullPath, {
    AgentFileSkillScriptRunner? runner,
  }) : _runner = runner;

  static const JsonElement defaultSchema = JsonElement({
    'type': 'array',
    'items': {'type': 'string'},
  });

  final AgentFileSkillScriptRunner? _runner;
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
    return runner(
      skill,
      this,
      arguments,
      serviceProvider,
      cancellationToken: cancellationToken,
    );
  }
}
