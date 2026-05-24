import 'agent_mode_provider.dart';

/// Options controlling the behavior of [AgentModeProvider].
class AgentModeProviderOptions {
  AgentModeProviderOptions();

  /// Custom instructions provided to the agent for using the mode tools.
  ///
  /// The instructions must contain a `{available_modes}` placeholder for the
  /// provider to inject the currently available list of modes, and a
  /// `{current_mode}` placeholder to inject the currently active mode.
  String? instructions;

  /// List of available modes the agent can operate in.
  List<AgentMode?>? modes;

  /// Initial mode for new sessions.
  String? defaultMode;
}

/// Represents an agent operating mode with a name and description.
class AgentMode {
  /// Creates an [AgentMode] with the given [name] and [description].
  AgentMode(String? name, String? description)
    : name = _throwIfNullOrWhitespace(name, 'name'),
      description = _throwIfNullOrWhitespace(description, 'description');

  /// Gets the name of the mode.
  final String name;

  /// Gets a description of when and how to use this mode.
  final String description;

  static String _throwIfNullOrWhitespace(String? value, String name) {
    if (value == null || value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be null or whitespace.');
    }
    return value;
  }
}
