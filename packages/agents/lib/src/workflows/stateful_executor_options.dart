import 'executor_options.dart';

/// Options for stateful executors.
class StatefulExecutorOptions<TState> extends ExecutorOptions {
  /// Creates stateful executor options.
  const StatefulExecutorOptions({
    this.initialState,
    this.stateFactory,
    super.supportsConcurrentSharedExecution,
    super.supportsResetting = true,
  });

  /// Gets a fixed initial state value.
  final TState? initialState;

  /// Gets a callback that creates the initial state.
  final TState Function()? stateFactory;

  /// Creates a state instance.
  TState? createInitialState() =>
      stateFactory != null ? stateFactory!() : initialState;
}
