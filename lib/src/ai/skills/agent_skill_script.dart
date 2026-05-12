import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import 'agent_skill.dart';
import '../../json_stubs.dart';

/// Abstract base class for skill scripts. A script represents an executable
/// action associated with a skill.
abstract class AgentSkillScript {
  /// Initializes a new instance of the [AgentSkillScript] class.
  ///
  /// [name] The script name.
  ///
  /// [description] An optional description of the script.
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
  /// Returns: The script execution result.
  ///
  /// [skill] The skill that owns this script.
  ///
  /// [arguments] Raw JSON arguments for script execution, preserving the
  /// original format (Object or array) sent by the caller.
  ///
  /// [serviceProvider] Optional service provider for dependency injection.
  ///
  /// [cancellationToken] Cancellation token.
  Future<Object?> run(
    AgentSkill skill,
    JsonElement? arguments,
    ServiceProvider? serviceProvider, {
    CancellationToken? cancellationToken,
  });
}
