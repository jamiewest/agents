import 'dart:convert';
import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import '../agent_skill_resource.dart';

/// A file-path-backed skill resource. Reads content from a file on disk
/// relative to the skill directory.
class AgentFileSkillResource extends AgentSkillResource {
  /// Initializes a new instance of the [AgentFileSkillResource] class.
  ///
  /// [name] The resource name (relative path within the skill directory).
  ///
  /// [fullPath] The absolute file path to the resource.
  AgentFileSkillResource(String name, String fullPath)
      : fullPath = fullPath,
        super(name) {
  }

  /// Gets the absolute file path to the resource.
  final String fullPath;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    var reader = streamReader(this.fullPath, const Utf8Codec());
    return await reader.readToEndAsync();
  }
}
