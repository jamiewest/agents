import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'protocol_builder.dart';
import 'stateful_executor_options.dart';
import 'workflow_context.dart';

/// Provides a simple executor implementation that uses a single message
/// handler function to process incoming messages, and maintain state across
/// invocations.
///
/// [id] A unique identifier for the executor.
///
/// [initialStateFactory] A factory to initialize the state value to be used
/// by the executor.
///
/// [options] Configuration options for the executor. If `null`, default
/// options will be used.
///
/// [sentMessageTypes] Message types sent by the handler. Defaults to empty,
/// and will filter non-matching messages.
///
/// [outputTypes] Message types yielded as output by the handler. Defaults to
/// empty.
///
/// [declareCrossRunShareable] Declare that this executor may be used
/// simultaneously by multiple runs safely.
///
/// [TState] The type of state associated with this Executor.
///
/// [TInput] The type of input message.
///
/// [TOutput] The type of output message.
abstract class StatefulExecutor<TState,TInput,TOutput> extends StatefulExecutor<TState> implements MessageHandler<TInput, TOutput> {
  /// Provides a simple executor implementation that uses a single message
  /// handler function to process incoming messages, and maintain state across
  /// invocations.
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [initialStateFactory] A factory to initialize the state value to be used
  /// by the executor.
  ///
  /// [options] Configuration options for the executor. If `null`, default
  /// options will be used.
  ///
  /// [sentMessageTypes] Message types sent by the handler. Defaults to empty,
  /// and will filter non-matching messages.
  ///
  /// [outputTypes] Message types yielded as output by the handler. Defaults to
  /// empty.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ///
  /// [TState] The type of state associated with this Executor.
  ///
  /// [TInput] The type of input message.
  ///
  /// [TOutput] The type of output message.
  StatefulExecutor(
    String id,
    TState Function() initialStateFactory,
    {StatefulExecutorOptions? options = null, Iterable<Type>? sentMessageTypes = null, Iterable<Type>? outputTypes = null, bool? declareCrossRunShareable = null, },
  );

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    var handlerDelegate = this.handleAsync;
    return protocolBuilder.configureRoutes((routeBuilder) => routeBuilder.addHandler(handlerDelegate))
                              .addMethodAttributeTypes(handlerDelegate.method)
                              .addClassAttributeTypes(this.runtimeType)
                              .sendsMessageTypes(sentMessageTypes ?? [])
                              .yieldsOutputTypes(outputTypes ?? []);
  }

  @override
  Future<TOutput> handle(
    TInput message,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  );
}
/// Provides a simple executor implementation that uses a single message
/// handler function to process incoming messages, and maintain state across
/// invocations.
///
/// [id] A unique identifier for the executor.
///
/// [initialStateFactory] A factory to initialize the state value to be used
/// by the executor.
///
/// [options] Configuration options for the executor. If `null`, default
/// options will be used.
///
/// [sentMessageTypes] Message types sent by the handler. Defaults to empty,
/// and will filter non-matching messages.
///
/// [outputTypes] Message types yielded as output by the handler. Defaults to
/// empty.
///
/// [declareCrossRunShareable] Declare that this executor may be used
/// simultaneously by multiple runs safely.
///
/// [TState] The type of state associated with this Executor.
///
/// [TInput] The type of input message.
abstract class StatefulExecutor<TState,TInput> extends StatefulExecutor<TState> implements MessageHandler<TInput> {
  /// Provides a simple executor implementation that uses a single message
  /// handler function to process incoming messages, and maintain state across
  /// invocations.
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [initialStateFactory] A factory to initialize the state value to be used
  /// by the executor.
  ///
  /// [options] Configuration options for the executor. If `null`, default
  /// options will be used.
  ///
  /// [sentMessageTypes] Message types sent by the handler. Defaults to empty,
  /// and will filter non-matching messages.
  ///
  /// [outputTypes] Message types yielded as output by the handler. Defaults to
  /// empty.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ///
  /// [TState] The type of state associated with this Executor.
  ///
  /// [TInput] The type of input message.
  StatefulExecutor(
    String id,
    TState Function() initialStateFactory,
    {StatefulExecutorOptions? options = null, Iterable<Type>? sentMessageTypes = null, Iterable<Type>? outputTypes = null, bool? declareCrossRunShareable = null, },
  );

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    var handlerDelegate = this.handleAsync;
    return protocolBuilder.configureRoutes((routeBuilder) => routeBuilder.addHandler(handlerDelegate))
                              .addMethodAttributeTypes(handlerDelegate.method)
                              .addClassAttributeTypes(this.runtimeType)
                              .sendsMessageTypes(sentMessageTypes ?? [])
                              .yieldsOutputTypes(outputTypes ?? []);
  }

  @override
  Future handle(TInput message, WorkflowContext context, {CancellationToken? cancellationToken, });
}
/// Provides a base class for executors that maintain and manage state across
/// multiple message handling operations.
///
/// [TState] The type of state associated with this Executor.
abstract class StatefulExecutor<TState> extends Executor {
  /// Initializes the executor with a unique id and an initial value for the
  /// state.
  ///
  /// [id] The unique identifier for this executor instance. Cannot be null or
  /// empty.
  ///
  /// [initialStateFactory] A factory to initialize the state value to be used
  /// by the executor.
  ///
  /// [options] Optional configuration settings for the executor. If null,
  /// default options are used.
  ///
  /// [declareCrossRunShareable] true to declare that the executor's state can
  /// be shared across multiple runs; otherwise, false.
  StatefulExecutor(
    String id,
    TState Function() initialStateFactory,
    {StatefulExecutorOptions? options = null, bool? declareCrossRunShareable = null, },
  ) : _initialStateFactory = initialStateFactory {
    this.options = (StatefulExecutorOptions)super.options;
  }

  final TState Function() _initialStateFactory;

  late TState? _stateCache;

  late final StatefulExecutorOptions options;

  String get defaultStateKey {
    return '${this.runtimeType.toString()}.state';
  }

  /// Gets the key used to identify the executor's state.
  String get stateKey {
    return this.options.stateKey ?? this.defaultStateKey;
  }

  /// Reads the state associated with this executor. If it is not initialized,
  /// it will be set to the initial state.
  ///
  /// Returns:
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [skipCache] Ignore the cached value, if any. State is not cached when
  /// running in Cross-Run Shareable mode.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future<TState> readState(
    WorkflowContext context,
    {bool? skipCache, CancellationToken? cancellationToken, },
  ) async  {
    if (!skipCache && this._stateCache != null) {
      return this._stateCache;
    }
    var state = await context.readOrInitStateAsync(
      this.stateKey,
      this._initialStateFactory,
      this.options.scopeName,
      cancellationToken,
    )
                                     ;
    if (!context.concurrentRunsEnabled) {
      this._stateCache = state;
    }
    return state;
  }

  /// Queues up an update to the executor's state.
  ///
  /// Returns:
  ///
  /// [state] The new value of state.
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future queueStateUpdate(
    TState state,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) {
    if (!context.concurrentRunsEnabled) {
      this._stateCache = state;
    }
    return context.queueStateUpdate(
      this.stateKey,
      state,
      this.options.scopeName,
      cancellationToken,
    );
  }

  /// Invokes an asynchronous operation that reads, updates, and persists
  /// workflow state associated with the specified key.
  ///
  /// Returns: A ValueTask that represents the asynchronous operation.
  ///
  /// [invocation] A delegate that receives the current state, workflow context,
  /// and cancellation token, and returns the updated state asynchronously.
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [skipCache] Ignore the cached value, if any. State is not cached when
  /// running in Cross-Run Shareable mode.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future invokeWithState(
    Func3<TState, WorkflowContext, CancellationToken, Future<TState?>> invocation,
    WorkflowContext context,
    {bool? skipCache, CancellationToken? cancellationToken, },
  ) async  {
    if (!skipCache && !context.concurrentRunsEnabled) {
      if (this._stateCache == null) {
        this._stateCache = await context.readOrInitStateAsync(
          this.stateKey,
          this._initialStateFactory,
          this.options.scopeName,
          cancellationToken,
        )
                                                ;
      }
      var newState = await invocation(this._stateCache ?? this._initialStateFactory(),
                                               context,
                                               cancellationToken)
                           ?? this._initialStateFactory();
      await context.queueStateUpdate(this.stateKey,
                                                newState,
                                                this.options.scopeName,
                                                cancellationToken);
      this._stateCache = newState;
    } else {
      await context.invokeWithState(invocation,
                                               this.stateKey,
                                               this._initialStateFactory,
                                               this.options.scopeName,
                                               cancellationToken)
                         ;
    }
  }

  Future reset() {
    this._stateCache = this._initialStateFactory();
    return Future.value();
  }
}
