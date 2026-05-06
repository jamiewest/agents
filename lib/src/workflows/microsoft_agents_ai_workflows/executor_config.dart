import 'identified.dart';

/// Represents a configuration for an Object with a String identifier. For
/// example, [Identified] Object.
///
/// [id] A unique identifier for the configurable Object.
///
/// [TOptions] Optional type of options for the configurable Object.
class ExecutorConfig<TOptions> {
  /// Represents a configuration for an Object with a String identifier.
  ///
  /// [id] A unique identifier for the configurable Object.
  ///
  /// [options] The options for the configurable Object.
  ExecutorConfig(String id, {TOptions? options})
      : id = id,
        options = options;

  /// Gets a unique identifier for the configurable Object.
  ///
  /// Remarks: If not provided, the configured Object will generate its own
  /// identifier.
  final String id;

  /// Gets the options for the configured Object.
  final TOptions? options;
}
