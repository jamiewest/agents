import '../../json_stubs.dart';

/// Provides utility methods for working with JSON data in the context of agents.
class AgentJsonUtilities {
  AgentJsonUtilities._();

  /// Gets the [JsonSerializerOptions] singleton used as the default in JSON
  /// serialization operations.
  static final JsonSerializerOptions defaultOptions = createDefaultOptions();

  /// Creates default options to use for agents-related serialization.
  static JsonSerializerOptions createDefaultOptions() {
    final options = JsonSerializerOptions();
    options.makeReadOnly();
    return options;
  }
}
