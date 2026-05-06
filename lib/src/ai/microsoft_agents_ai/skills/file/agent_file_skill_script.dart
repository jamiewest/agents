import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import '../agent_skill.dart';
import '../agent_skill_script.dart';
import 'agent_file_skill.dart';
import 'agent_file_skill_script_runner.dart';
import 'agent_file_skills_source.dart';
import '../../../../json_stubs.dart';

/// A file-path-backed skill script. Represents a script file on disk that
/// requires an external runner to run.
class AgentFileSkillScript extends AgentSkillScript {
  /// Initializes a new instance of the [AgentFileSkillScript] class.
  ///
  /// [name] The script name.
  ///
  /// [fullPath] The absolute file path to the script.
  ///
  /// [runner] Optional external runner for running the script. An
  /// [InvalidOperationException] is thrown from [CancellationToken)] if no
  /// runner is provided.
  AgentFileSkillScript(
    String name,
    String fullPath,
    {AgentFileSkillScriptRunner? runner = null, }
  ) : fullPath = fullPath,
      super(name) {
    this._runner = runner;
  }

  /// Cached JSON schema element describing the expected argument format: a
  /// String array of CLI arguments.
  static final JsonElement s_defaultSchema = CreateDefaultSchema();

  late final AgentFileSkillScriptRunner? _runner;

  /// Gets the absolute file path to the script.
  final String fullPath;

  /// Returns a fixed schema describing a String array of CLI arguments:
  /// {"type":"array","items":{"type":"String"}}.
  ///
  /// Remarks: Returns a fixed schema describing a String array of CLI
  /// arguments: `{"type":"array","items":{"type":"String"}}`.
  JsonElement? get parametersSchema {
    return s_defaultSchema;
  }

  @override
  Future<Object?> run(
    AgentSkill skill,
    JsonElement? arguments,
    ServiceProvider? serviceProvider,
    {CancellationToken? cancellationToken, }
  ) async {
    if (skill is! AgentFileSkill) {
      throw StateError("File-based script ${this.name} requires an ${"AgentFileSkill"} but received ${skill.runtimeType.toString()}.");
    }
    if (this._runner == null) {
      throw StateError(
                'Script ${this.name} cannot be executed because no AgentFileSkillScriptRunner was provided. '
                'Supply a script runner when constructing AgentFileSkillsSource to enable script execution.');
    }
    return await this._runner(
      fileSkill,
      this,
      arguments,
      serviceProvider,
      cancellationToken,
    ) ;
  }

  static JsonElement createDefaultSchema() {
    var document = JsonDocument.parse("""{"type":"array","items":{"type":"String"}}""");
    return document.rootElement.clone();
  }
}
