import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import 'agent_skill.dart';
import '../../json_stubs.dart';

/// Abstract base class for skill scripts. A script represents an executable
/// action associated with a skill.
abstract class AgentSkillScript {
  /// Creates an [AgentSkillScript] with the given [name] and optional
  /// [description].
  AgentSkillScript(this.name, {this.description});

  /// Gets the script name.
  final String name;

  /// Gets the optional script description.
  String? description;

  /// Gets the JSON schema describing the parameters accepted by this script, or
  /// `null` if not available.
  JsonElement? get parametersSchema {
    return null;
  }

  /// Runs the script with the given arguments.
  ///
  /// Returns the script execution result.
  Future<Object?> run(
    AgentSkill skill,
    JsonElement? arguments,
    ServiceProvider? serviceProvider, {
    CancellationToken? cancellationToken,
  });
}
