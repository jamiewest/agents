import 'executor_options.dart';

/// .
class StatefulExecutorOptions extends ExecutorOptions {
  StatefulExecutorOptions();

  /// Gets or sets the unique key that identifies the executor's state. If not
  /// provided, will default to `{ExecutorType}.State`.
  String? stateKey;

  /// Gets or sets the scope name to use for the executor's state. If not
  /// provided, the state will be private to this executor instance.
  String? scopeName;
}
