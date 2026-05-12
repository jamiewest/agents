import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';

/// Abstract base class for skill resources. A resource provides supplementary
/// content (references, assets) to a skill.
abstract class AgentSkillResource {
  /// Initializes a new instance of the [AgentSkillResource] class.
  ///
  /// [name] The resource name (e.g., relative path or identifier).
  ///
  /// [description] An optional description of the resource.
  AgentSkillResource(this.name, {this.description});

  /// Gets the resource name.
  final String name;

  /// Gets the optional resource description.
  String? description;

  /// Reads the resource content asynchronously.
  ///
  /// Returns: The resource content.
  ///
  /// [serviceProvider] Optional service provider for dependency injection.
  ///
  /// [cancellationToken] Cancellation token.
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  });
}
