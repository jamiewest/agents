import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'execution/call_result.dart';
import 'execution/message_router.dart';
import 'external_request_context.dart';
import 'external_response.dart';
import 'port_binding.dart';
import 'portable_value.dart';
import 'workflow_context.dart';

/// Provides a builder for configuring message type handlers for an
/// [Executor].
class RouteBuilder {
  RouteBuilder(ExternalRequestContext? externalRequestContext) : _externalRequestContext = externalRequestContext {
  }

  final ExternalRequestContext? _externalRequestContext;

  final Map<Type, Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>>> _typedHandlers = {};

  final Map<Type, Type> _outputTypes = {};

  final Map<String, Func3<ExternalResponse, WorkflowContext, CancellationToken, Future<ExternalResponse?>>> _portHandlers = {};

  Func3<PortableValue, WorkflowContext, CancellationToken, Future<CallResult>>? _catchAll;

  RouteBuilder addHandlerInternal(
    Type messageType,
    Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>> handler,
    Type? outputType,
    {bool? overwrite, },
  ) {
    if (messageType == PortableValue) {
      throw StateError("Cannot register a handler for PortableValue. Use addCatchAll() instead.");
    }
    assert(CallResult != outputType, "Must not double-wrap message handlers in the RouteBuilder. " +
            "Use addHandlerInternal() or do not wrap user-provided handler.");
    if (this._typedHandlers.containsKey(messageType) == overwrite) {
      this._typedHandlers[messageType] = handler;
      if (outputType != null) {
        this._outputTypes[messageType] = outputType;
      } else {
        this._outputTypes.remove(messageType);
      }
    } else if (overwrite) {
      throw ArgumentError('A handler for message type ${messageType.fullName} has not yet been registered (overwrite = true).');
    } else if (!overwrite) {
      throw ArgumentError('A handler for message type ${messageType.fullName} is already registered (overwrite = false).');
    }
    return this;
  }

  RouteBuilder addHandlerUntyped(
    Type type,
    bool overwrite,
    {Func3<Object, WorkflowContext, CancellationToken, Future>? handler, },
  ) {
    return this.addHandlerInternal(type, WrappedHandlerAsync, outputType: null, overwrite);
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<CallResult> WrappedHandlerAsync(Object message, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             await handler.Invoke(message, context, cancellationToken);
      //             return CallResult.ReturnVoid();
      //         }
  }

  /// Registers a port and associated handler for external requests originating
  /// from the executor. This generates a PortBinding that can be used to submit
  /// requests through to the workflow Run call.
  ///
  /// Returns: The current [RouteBuilder] instance, enabling fluent
  /// configuration of additional handlers or route options.
  ///
  /// [id] A unique identifier for the port.
  ///
  /// [handler] A delegate that processes messages of type `TResponse` within
  /// the workflow context. The delegate is invoked for each incoming response
  /// to requests through this port.
  ///
  /// [portBinding] A [PortBinding] representing this port registration
  /// providing a means to submit requests.
  ///
  /// [overwrite] Set `true` to replace an existing handler for the specified
  /// response; if a port with this id is not this will throw. If set to `false`
  /// and a handler is registered, this will throw.
  ///
  /// [TRequest] The type of request messages that will be sent through this
  /// port.
  ///
  /// [TResponse] The type of response messages that will be sent through this
  /// port.
  (
    RouteBuilder,
    PortBinding?,
  ) addPortHandler<TRequest,TResponse>(String id, Func3<TResponse, WorkflowContext, CancellationToken, Future> handler, {bool? overwrite, }) {
    var portBinding = null;
    if (this._externalRequestContext == null) {
      throw StateError("An external request context is required to register port handlers.");
    }
    var port = RequestPort.create<TRequest, TResponse>(id);
    var sink = this._externalRequestContext!.registerPort(port);
    portBinding = new(port, sink);
    if (this._portHandlers.containsKey(id) == overwrite) {
      this._portHandlers[id] = InvokeHandlerAsync;
    } else if (overwrite) {
      throw StateError('A handler for port id ${id} is! registered (overwrite = true).');
    } else {
      throw StateError('A handler for port id ${id} is already registered (overwrite = false).');
    }
    return (this, portBinding);
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<ExternalResponse?> InvokeHandlerAsync(ExternalResponse response, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             if (!response.TryGetDataAs(typedResponse))
      //             {
        //                 throw new InvalidOperationException($"Received response data is not of expected type {TResponse.FullName} for port {port.Id}.");
        //             }
      //
      //             await handler(typedResponse, context, cancellationToken);
      //             return response;
      //         }
  }

  /// Registers a handler for messages of the specified input type in the
  /// workflow route.
  ///
  /// Remarks: If a handler for the specified input type already exists and
  /// `overwrite` is `false`, the existing handler will not be replaced.
  /// Handlers are invoked asynchronously and are expected to complete their
  /// processing before the workflow continues.
  ///
  /// Returns: The current [RouteBuilder] instance, enabling fluent
  /// configuration of additional handlers or route options.
  ///
  /// [handler] A delegate that processes messages of type `TInput` within the
  /// workflow context. The delegate is invoked for each incoming message of the
  /// specified type.
  ///
  /// [overwrite] Set `true` to replace an existing handler for the specified
  /// input type; if no handler is registered will throw. If set to `false` and
  /// a handler is registered, this will throw.
  ///
  /// [TInput]
  RouteBuilder addHandler<TInput>(
    bool overwrite,
    {Action3<TInput, WorkflowContext, CancellationToken>? handler, },
  ) {
    return this.addHandlerInternal(
      TInput,
      WrappedHandlerAsync,
      outputType: null,
      overwrite,
    );
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<CallResult> WrappedHandlerAsync(Object message, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             handler.Invoke((TInput)message, context, cancellationToken);
      //             return CallResult.ReturnVoid();
      //         }
  }

  RouteBuilder addCatchAll(
    bool overwrite,
    {Func3<PortableValue, WorkflowContext, CancellationToken, Future<CallResult>>? handler, },
  ) {
    if (!overwrite && this._catchAll != null) {
      throw StateError("A catch-all is already registered (overwrite = false).");
    }
    this._catchAll = handler;
    return this;
  }

  void registerPortHandlerRouter() {
    var portHandlers = this._portHandlers;
    this.addHandler<ExternalResponse, ExternalResponse?>(InvokeHandlerAsync);
    /* TODO: unsupported node kind "unknown" */
    // ValueTask<ExternalResponse?> InvokeHandlerAsync(ExternalResponse response, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             if (portHandlers.TryGetValue(response.PortInfo.PortId, portHandler))
      //             {
        //                 return portHandler(response, context, cancellationToken);
        //             }
      //
      //             throw new InvalidOperationException($"Unknown port {response.PortInfo}");
      //         }
  }

  Iterable<Type> get outputTypes {
    return this._outputTypes.values;
  }

  MessageRouter build() {
    if (this._portHandlers.length > 0) {
      this.registerPortHandlerRouter();
    }
    return new(this._typedHandlers, [.. this._outputTypes.values], this._catchAll);
  }
}
