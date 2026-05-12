import 'executor_config.dart';

/// Pairs a workflow object with configuration.
class Configured<T> {
  /// Creates a configured value.
  const Configured(this.value, this.config);

  /// Gets the configured value.
  final T value;

  /// Gets the associated configuration.
  final ExecutorConfig config;

  /// Deconstructs to a Dart record, mirroring the C# configured pair.
  ({T value, ExecutorConfig config}) toRecord() =>
      (value: value, config: config);
}

/// Configuration helpers.
extension ConfiguredExtensions<T> on T {
  /// Associates this value with [config].
  Configured<T> configured([ExecutorConfig config = const ExecutorConfig()]) =>
      Configured<T>(this, config);
}
