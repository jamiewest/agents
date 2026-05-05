/// Represents the YAML frontmatter metadata parsed from a SKILL.md file.
///
/// Remarks: Frontmatter is the L1 (discovery) layer of the Agent Skills
/// specification . It contains the minimal metadata needed to advertise a
/// skill in the system prompt without loading the full skill content. The
/// constructor validates the name and description against specification rules
/// and throws [ArgumentException] if either value is invalid.
class AgentSkillFrontmatter {
  /// Initializes a new instance of the [AgentSkillFrontmatter] class.
  ///
  /// [name] Skill name in kebab-case.
  ///
  /// [description] Skill description for discovery.
  ///
  /// [compatibility] Optional compatibility information (max 500 chars).
  AgentSkillFrontmatter(
    String name,
    String description,
    {String? compatibility = null, },
  ) :
      name = name,
      description = description {
    {
      String? reason;
      if (!validateName(name) ||
            !validateDescription(description, reason) ||
            !validateCompatibility(compatibility, reason)) {
        throw ArgumentError(reason);
      }
    }
    this._compatibility = compatibility;
  }

  static final RegExp s_validNameRegex = new(
    "^[a-z0-9]([a-z0-9]*-[a-z0-9])*[a-z0-9]*$",
  );

  late String? _compatibility;

  /// Gets the skill name. Lowercase letters, numbers, and hyphens only; no
  /// leading, trailing, or consecutive hyphens.
  final String name;

  /// Gets the skill description. Used for discovery in the system prompt.
  final String description;

  /// Gets or sets an optional license name or reference.
  String? license;

  /// Gets or sets optional compatibility information (max 500 chars).
  String? compatibility;

  /// Gets or sets optional space-delimited list of pre-approved tools.
  String? allowedTools;

  /// Gets or sets the arbitrary key-value metadata for this skill.
  AdditionalPropertiesDictionary? metadata;

  /// Validates a skill name against specification rules.
  ///
  /// Returns: `true` if the name is valid; otherwise, `false`.
  ///
  /// [name] The skill name to validate (may be `null`).
  ///
  /// [reason] When validation fails, contains a human-readable description of
  /// the failure.
  static (bool, String??) validateName(String? name) {
    if ((name == null || name.trim().isEmpty)) {
      return (false, "Skill name is required.");
    }
    if (name.length > MaxNameLength) {
      return (false, 'Skill name must be ${MaxNameLength} characters or fewer.');
    }
    if (!s_validNameRegex.isMatch(name)) {
      return (
        false,
        'Skill name must use only lowercase letters, numbers, and hyphens, '
        'and must not start or end with a hyphen or contain consecutive hyphens.',
      );
    }
    return (true, null);
  }

  /// Validates a skill description against specification rules.
  ///
  /// Returns: `true` if the description is valid; otherwise, `false`.
  ///
  /// [description] The skill description to validate (may be `null`).
  ///
  /// [reason] When validation fails, contains a human-readable description of
  /// the failure.
  static (bool, String??) validateDescription(String? description) {
    if ((description == null || description.trim().isEmpty)) {
      return (false, "Skill description is required.");
    }
    if (description.length > MaxDescriptionLength) {
      return (false, 'Skill description must be ${MaxDescriptionLength} characters or fewer.');
    }
    return (true, null);
  }

  /// Validates an optional skill compatibility value against specification
  /// rules.
  ///
  /// Returns: `true` if the value is valid; otherwise, `false`.
  ///
  /// [compatibility] The optional compatibility value to validate (may be
  /// `null`).
  ///
  /// [reason] When validation fails, contains a human-readable description of
  /// the failure.
  static (bool, String??) validateCompatibility(String? compatibility) {
    if (compatibility?.length > MaxCompatibilityLength) {
      return (false, 'Skill compatibility must be ${MaxCompatibilityLength} characters or fewer.');
    }
    return (true, null);
  }
}
