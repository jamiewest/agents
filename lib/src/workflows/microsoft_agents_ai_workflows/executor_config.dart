import 'identified.dart';

/// Represents a configuration for an Object with a String identifier. For
/// example, [Identified] Object.
///
/// [id] A unique identifier for the configurable Object.
class ExecutorConfig {
  /// Represents a configuration for an Object with a String identifier. For
  /// example, [Identified] Object.
  ///
  /// [id] A unique identifier for the configurable Object.
  const ExecutorConfig(String id) : id = id;

  /// Gets a unique identifier for the configurable Object.
  ///
  /// Remarks: If not provided, the configured Object will generate its own
  /// identifier.
  String get id {
    return id;
  }
}

/// Represents a configuration for an Object with a String identifier and
/// options of type `TOptions`.
///
/// [id] A unique identifier for the configurable Object.
///
/// [options] The options for the configurable Object.
///
/// [TOptions] The type of options for the configurable Object.
class ExecutorConfig<TOptions> extends ExecutorConfig {
  /// Represents a configuration for an Object with a String identifier and
  /// options of type `TOptions`.
  ///
  /// [id] A unique identifier for the configurable Object.
  ///
  /// [options] The options for the configurable Object.
  ///
  /// [TOptions] The type of options for the configurable Object.
  ExecutorConfig(String id, {TOptions? options}) : super(id);

  /// Gets the options for the configured Object.
  TOptions? get options {
    return options;
  }
}
