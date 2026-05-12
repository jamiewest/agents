import 'dart:io';
import 'package:extensions/system.dart';
import 'package:extensions/dependency_injection.dart';
import '../agent_skill_resource.dart';

/// A file-path-backed skill resource. Reads content from a file on disk
/// relative to the skill directory.
class AgentFileSkillResource extends AgentSkillResource {
  /// Creates an [AgentFileSkillResource] with the given [name] and [fullPath].
  AgentFileSkillResource(super.name, this.fullPath);

  /// Gets the absolute file path to the resource.
  final String fullPath;

  @override
  Future<Object?> read({
    ServiceProvider? serviceProvider,
    CancellationToken? cancellationToken,
  }) async {
    return await File(fullPath).readAsString();
  }
}
