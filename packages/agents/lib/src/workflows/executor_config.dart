import 'executor_options.dart';

/// Configuration applied while creating or binding an executor.
class ExecutorConfig {
  /// Creates an executor config.
  const ExecutorConfig({
    this.id,
    this.options,
    this.properties = const <String, Object?>{},
  });

  /// Gets an optional executor identifier override.
  final String? id;

  /// Gets executor runtime options.
  final ExecutorOptions? options;

  /// Gets arbitrary configuration properties.
  final Map<String, Object?> properties;

  /// Creates a copy with selected values replaced.
  ExecutorConfig copyWith({
    String? id,
    ExecutorOptions? options,
    Map<String, Object?>? properties,
  }) => ExecutorConfig(
    id: id ?? this.id,
    options: options ?? this.options,
    properties: properties ?? this.properties,
  );
}
