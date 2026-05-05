import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'executor_options.dart';
import 'protocol_builder.dart';
import 'workflow_context.dart';

/// Executes a user-provided asynchronous function in response to workflow
/// messages of the specified input type,
///
/// [id] A unique identifier for the executor.
///
/// [handlerAsync] A delegate that defines the asynchronous function to
/// execute for each input message.
///
/// [options] Configuration options for the executor. If `null`, default
/// options will be used.
///
/// [sentMessageTypes] Additional message types sent by the handler. Defaults
/// to empty, and will filter non-matching messages.
///
/// [outputTypes] Additional message types yielded as output by the handler.
/// Defaults to empty.
///
/// [declareCrossRunShareable] Declare that this executor may be used
/// simultaneously by multiple runs safely.
///
/// [TInput] The type of input message.
///
/// [TOutput] The type of output message.
class FunctionExecutor<TInput, TOutput> extends Executor<TInput, TOutput> {
  /// Executes a user-provided asynchronous function in response to workflow
  /// messages of the specified input type,
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [handlerAsync] A delegate that defines the asynchronous function to
  /// execute for each input message.
  ///
  /// [options] Configuration options for the executor. If `null`, default
  /// options will be used.
  ///
  /// [sentMessageTypes] Additional message types sent by the handler. Defaults
  /// to empty, and will filter non-matching messages.
  ///
  /// [outputTypes] Additional message types yielded as output by the handler.
  /// Defaults to empty.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ///
  /// [TInput] The type of input message.
  ///
  /// [TOutput] The type of output message.
  FunctionExecutor(
    String id,
    ExecutorOptions? options,
    Iterable<Type>? sentMessageTypes,
    Iterable<Type>? outputTypes,
    bool declareCrossRunShareable, {
    Func3<TInput, WorkflowContext, CancellationToken, Future<TOutput>>?
        handlerAsync =
        null,
    Func3<TInput, WorkflowContext, CancellationToken, TOutput>? handlerSync =
        null,
  });

  static (
    Func3<TInput, WorkflowContext, CancellationToken, Future<TOutput>>,
    Iterable<Type>?,
    Iterable<Type>?,
  )
  wrapFunc(
    Func3<TInput, WorkflowContext, CancellationToken, TOutput> handlerSync,
  ) {
    var sentTypes = null;
    var yieldedTypes = null;
    if (handlerSync.method != null) {
      var method = handlerSync.method;
      (sentTypes, yieldedTypes) = method.getAttributeTypes();
    } else {
      sentTypes = yieldedTypes = [];
    }
    return (RunFuncAsync, sentTypes, yieldedTypes);
    /* TODO: unsupported node kind "unknown" */
    // ValueTask<TOutput> RunFuncAsync(TInput input, IWorkflowContext workflowContext, CancellationToken cancellationToken)
    //         {
    //             TOutput result = handlerSync(input, workflowContext, cancellationToken);
    //             return new ValueTask<TOutput>(result);
    //         }
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return base
        .configureProtocol(protocolBuilder)
        // We have to register the delegate handlers here because the base class gets the RunFuncAsync local function in
        // WrapFunc, which cannot have the right annotations.
        .addDelegateAttributeTypes(handlerAsync)
        .sendsMessageTypes(sentMessageTypes ?? [])
        .yieldsOutputTypes(outputTypes ?? []);
  }

  @override
  Future<TOutput> handle(
    TInput message,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    return handlerAsync(message, context, cancellationToken);
  }
}

/// Executes a user-provided asynchronous function in response to workflow
/// messages of the specified input type.
///
/// [id] A unique identifier for the executor.
///
/// [handlerAsync] A delegate that defines the asynchronous function to
/// execute for each input message.
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
/// [TInput] The type of input message.
class FunctionExecutor<TInput> extends Executor<TInput> {
  /// Executes a user-provided asynchronous function in response to workflow
  /// messages of the specified input type.
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [handlerAsync] A delegate that defines the asynchronous function to
  /// execute for each input message.
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
  /// [TInput] The type of input message.
  FunctionExecutor(
    String id,
    ExecutorOptions? options,
    Iterable<Type>? sentMessageTypes,
    Iterable<Type>? outputTypes,
    bool declareCrossRunShareable, {
    Func3<TInput, WorkflowContext, CancellationToken, Future>? handlerAsync =
        null,
    Action3<TInput, WorkflowContext, CancellationToken>? handlerSync = null,
  });

  static (
    Func3<TInput, WorkflowContext, CancellationToken, Future>,
    Iterable<Type>?,
    Iterable<Type>?,
  )
  wrapAction(Action3<TInput, WorkflowContext, CancellationToken> handlerSync) {
    var sentTypes = null;
    var yieldedTypes = null;
    if (handlerSync.method != null) {
      var method = handlerSync.method;
      (sentTypes, yieldedTypes) = method.getAttributeTypes();
    } else {
      sentTypes = yieldedTypes = [];
    }
    return (RunActionAsync, sentTypes, yieldedTypes);
    /* TODO: unsupported node kind "unknown" */
    // ValueTask RunActionAsync(TInput input, IWorkflowContext workflowContext, CancellationToken cancellationToken)
    //         {
    //             handlerSync(input, workflowContext, cancellationToken);
    //             return Future.value(null);
    //         }
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return base
        .configureProtocol(protocolBuilder)
        // We have to register the delegate handlers here because the base class gets the RunActionAsync local function in
        // WrapAction, which cannot have the right annotations.
        .addDelegateAttributeTypes(handlerAsync)
        .sendsMessageTypes(sentMessageTypes ?? [])
        .yieldsOutputTypes(outputTypes ?? []);
  }

  @override
  Future handle(
    TInput message,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    return handlerAsync(message, context, cancellationToken);
  }
}
