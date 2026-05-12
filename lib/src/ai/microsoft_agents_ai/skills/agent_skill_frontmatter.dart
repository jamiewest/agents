import 'package:extensions/ai.dart';

/// Represents the YAML frontmatter metadata parsed from a SKILL.md file.
class AgentSkillFrontmatter {
  AgentSkillFrontmatter(
    this.name,
    this.description, {
    String? compatibility,
    this.license,
    this.allowedTools,
    this.metadata,
  }) : _compatibility = compatibility {
    final (validName, nameReason) = validateName(name);
    if (!validName) {
      throw ArgumentError(nameReason);
    }
    final (validDescription, descriptionReason) = validateDescription(
      description,
    );
    if (!validDescription) {
      throw ArgumentError(descriptionReason);
    }
    final (validCompatibility, compatibilityReason) = validateCompatibility(
      compatibility,
    );
    if (!validCompatibility) {
      throw ArgumentError(compatibilityReason);
    }
  }

  static const int maxNameLength = 64;
  static const int maxDescriptionLength = 1024;
  static const int maxCompatibilityLength = 500;

  static final RegExp validNameRegex = RegExp(
    r'^[a-z0-9]([a-z0-9]*-[a-z0-9])*[a-z0-9]*$',
  );

  final String name;
  final String description;
  String? license;
  String? allowedTools;
  AdditionalPropertiesDictionary? metadata;

  String? _compatibility;
  String? get compatibility => _compatibility;
  set compatibility(String? value) {
    final (valid, reason) = validateCompatibility(value);
    if (!valid) {
      throw ArgumentError(reason);
    }
    _compatibility = value;
  }

  static (bool, String?) validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return (false, 'Skill name is required.');
    }
    if (name.length > maxNameLength) {
      return (false, 'Skill name must be $maxNameLength characters or fewer.');
    }
    if (!validNameRegex.hasMatch(name)) {
      return (
        false,
        'Skill name must use only lowercase letters, numbers, and hyphens, '
            'and must not start or end with a hyphen or contain consecutive hyphens.',
      );
    }
    return (true, null);
  }

  static (bool, String?) validateDescription(String? description) {
    if (description == null || description.trim().isEmpty) {
      return (false, 'Skill description is required.');
    }
    if (description.length > maxDescriptionLength) {
      return (
        false,
        'Skill description must be $maxDescriptionLength characters or fewer.',
      );
    }
    return (true, null);
  }

  static (bool, String?) validateCompatibility(String? compatibility) {
    if (compatibility != null &&
        compatibility.length > maxCompatibilityLength) {
      return (
        false,
        'Skill compatibility must be $maxCompatibilityLength characters or fewer.',
      );
    }
    return (true, null);
  }
}
