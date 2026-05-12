import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';

/// Abstract base class for skill resources. A resource provides supplementary
/// content (references, assets) to a skill.
abstract class AgentSkillResource {
  /// Creates an [AgentSkillResource] with the given [name] and optional
  /// [description].
  AgentSkillResource(this.name, {this.description});

  /// Gets the resource name.
  final String name;

  /// Gets the optional resource description.
  String? description;

  /// Reads the resource content asynchronously.
  ///
  /// Returns the resource content.
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  });
}
