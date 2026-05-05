import 'package:extensions/system.dart';
import 'request_port.dart';
import 'checkpointing/type_id.dart';
import 'execution/external_request_sink.dart';
import 'execution/message_router.dart';
import 'executor_completed_event.dart';
import 'executor_event.dart';
import 'executor_failed_event.dart';
import 'executor_invoked_event.dart';
import 'executor_options.dart';
import 'external_request.dart';
import 'external_request_context.dart';
import 'external_response.dart';
import 'identified.dart';
import 'observability/workflow_telemetry_context.dart';
import 'protocol_builder.dart';
import 'protocol_descriptor.dart';
import 'resettable_executor.dart';
import 'turn_token.dart';
import 'workflow.dart';
import 'workflow_context.dart';
import 'workflow_host_agent.dart';
import '../../map_extensions.dart';

class DelayedExternalRequestContext implements ExternalRequestContext {
  DelayedExternalRequestContext({ExternalRequestContext? targetContext = null}) {
    this._targetContext = targetContext;
  }

  final Map<String, RequestPortPort, DelayRegisteredSinkSink> _requestPorts = {};

  late ExternalRequestContext? _targetContext;

  void applyPortRegistrations(ExternalRequestContext targetContext) {
    this._targetContext = targetContext;
    /* TODO: unsupported node kind "unknown" */
    // foreach ((RequestPort requestPort, DelayRegisteredSink? sink) in this._requestPorts.Values)
    //         {
      //             sink?.TargetSink = targetContext.RegisterPort(requestPort);
      //         }
  }

  @override
  ExternalRequestSink registerPort(RequestPort port) {
    var delaySink = new()
        {
            TargetSink = this._targetContext?.registerPort(port),
        };
    this._requestPorts.add(port.id, (port, delaySink));
    return delaySink;
  }
}
class DelayRegisteredSink implements ExternalRequestSink {
  DelayRegisteredSink();

  late ExternalRequestSink? targetSink;

  @override
  Future post(ExternalRequest request) {
    return this.targetSink == null
                ? throw StateError("The external request sink has not been registered yet.")
                : this.targetSink.post(request);
  }
}
/// A component that processes messages in a [Workflow].
abstract class Executor implements Identified {
  /// Initialize the executor with a unique identifier
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [options] Configuration options for the executor. If `null`, default
  /// options will be used.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  Executor(
    String id,
    {ExecutorOptions? options = null, bool? declareCrossRunShareable = null, },
  ) : id = id {
    this.options = options ?? ExecutorOptions.defaultValue;
    //if (declareCrossRunShareable && this is IResettableExecutor)
        //{
        //    // We need a way to be able to let the user override this at the workflow level too, because knowing the fine
        //    // details of when to use which of these paths seems like it could be tricky, and we should not force users
        //    // to do this; instead container agents should set this when they intiate the run (via WorkflowHostAgent).
        //    throw ArgumentError("An executor that is declared as cross-run shareable cannot also be resettable.");
        //}

        this.isCrossRunShareable = declareCrossRunShareable;
  }

  /// A unique identifier for the executor.
  final String id;

  final DelayedExternalRequestContext delayedPortRegistrations;

  late final bool isCrossRunShareable;

  /// Gets the configuration options for the executor.
  late final ExecutorOptions options;

  ExecutorProtocol get protocol {
    return field ??= this.configureProtocol(new(this.delayedPortRegistrations)).build(this.options);
  }

  /// Configures the protocol by setting up routes and declaring the message
  /// types used for sending and yielding output.
  ///
  /// Remarks: This method serves as the primary entry point for protocol
  /// configuration. It integrates route setup and message type declarations.
  /// For backward compatibility, it is currently invoked from the RouteBuilder.
  ///
  /// Returns: An instance of [ExecutorProtocol] that represents the fully
  /// configured protocol.
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder);
  void attachRequestContext(ExternalRequestContext externalRequestContext) {
    // TODO: This is an unfortunate pattern (pending the ability to rework the Configure APIs a bit):
        // new()
        // >>> will throw InvalidOperationException if attachRequestContext() is! invoked when using PortHandlers
        //   .attachRequestContext()
        // >>> only usable now

        this.delayedPortRegistrations.applyPortRegistrations(externalRequestContext);
    _ = this.protocol;
  }

  /// Perform any asynchronous initialization required by the executor. This
  /// method is called once per executor instance,
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future initialize(WorkflowContext context, {CancellationToken? cancellationToken, }) {
    return Future.value(null);
  }

  MessageRouter get router {
    return this.protocol.router;
  }

  Future<Object?> executeCore(
    Object message,
    TypeId messageType,
    WorkflowContext context,
    {WorkflowTelemetryContext? telemetryContext, CancellationToken? cancellationToken, },
  ) async  {
    var activity = telemetryContext.startExecutorProcessActivity(
      this.id,
      this.runtimeType.fullName,
      messageType.typeName,
      message,
    );
    activity?.createSourceLinks(context.traceContext);
    await context.addEvent(
      executorInvokedEvent(this.id, message),
      cancellationToken,
    ) ;
    var result = await this.router.routeMessage(
      message,
      context,
      requireRoute: true,
      cancellationToken,
    )
                                              ;
    ExecutorEvent executionResult;
    if (result?.isSuccess is! false) {
      executionResult = executorCompletedEvent(this.id, result?.result);
    } else {
      executionResult = executorFailedEvent(this.id, result.exception);
    }
    await context.addEvent(executionResult, cancellationToken);
    if (result == null) {
      throw notSupportedException(
                'No handler found for message type ${message.runtimeType.toString()} in executor ${this.runtimeType.toString()}.');
    }
    if (!result.isSuccess) {
      throw targetInvocationException(
        'Error invoking handler for ${message.runtimeType}',
        result.exception,
      );
    }
    if (result.isVoid) {
      return null;
    }
    // Output is! available if executor does not return anything, in which case
        // messages sent in the handlers of this executor will be set in the message
        // send activities.
        telemetryContext.setExecutorOutput(activity, result.result);
    if (result.result != null && this.options.autoSendMessageHandlerResultObject) {
      await context.sendMessage(
        result.result,
        cancellationToken: cancellationToken,
      ) ;
    }
    if (result.result != null && this.options.autoYieldOutputHandlerResultObject) {
      await context.yieldOutput(result.result, cancellationToken);
    }
    return result.result;
  }

  /// Invoked once per superstep before any messages are delivered to the
  /// Executor.
  ///
  /// Returns: A ValueTask representing the asynchronous operation.
  ///
  /// [context] The workflow context.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future onMessageDeliveryStarting(
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) {
    return Future.value(null);
  }

  /// Invoked once per superstep after all messages have been delivered to the
  /// Executor.
  ///
  /// Returns: A ValueTask representing the asynchronous operation.
  ///
  /// [context] The workflow context.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future onMessageDeliveryFinished(
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  ) {
    return Future.value(null);
  }

  /// Invoked before a checkpoint is saved, allowing custom pre-save logic in
  /// derived classes.
  ///
  /// Returns: A ValueTask representing the asynchronous operation.
  ///
  /// [context] The workflow context.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future onCheckpointing(WorkflowContext context, {CancellationToken? cancellationToken, }) {
    return Future.value(null);
  }

  /// Invoked after a checkpoint is loaded, allowing custom post-load logic in
  /// derived classes.
  ///
  /// Returns: A ValueTask representing the asynchronous operation.
  ///
  /// [context] The workflow context.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests. The default is [None].
  Future onCheckpointRestored(WorkflowContext context, {CancellationToken? cancellationToken, }) {
    return Future.value(null);
  }

  /// A set of [Type]s, representing the messages this executor can handle.
  Set<Type> get inputTypes {
    return this.router.incomingTypes;
  }

  /// A set of [Type]s, representing the messages this executor can produce as
  /// output.
  Set<Type> get outputTypes {
    return field ??= Set<Type>(this.protocol.describe().yields);
  }

  /// Describes the protocol for communication with this [Executor].
  ///
  /// Returns:
  ProtocolDescriptor describeProtocol() {
    return this.protocol.describe();
  }

  /// Checks if the executor can handle a specific message type.
  ///
  /// Returns:
  ///
  /// [messageType]
  bool canHandle(Type messageType) {
    return this.protocol.canHandle(messageType);
  }

  bool canOutput(Type messageType) {
    return this.protocol.canOutput(messageType);
  }
}
/// Provides a simple executor implementation that uses a single message
/// handler function to process incoming messages.
///
/// [id] A unique identifier for the executor.
///
/// [options] Configuration options for the executor. If `null`, default
/// options will be used.
///
/// [declareCrossRunShareable] Declare that this executor may be used
/// simultaneously by multiple runs safely.
///
/// [TInput] The type of input message.
///
/// [TOutput] The type of output message.
abstract class Executor<TInput,TOutput> extends Executor implements MessageHandler<TInput, TOutput> {
  /// Provides a simple executor implementation that uses a single message
  /// handler function to process incoming messages.
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [options] Configuration options for the executor. If `null`, default
  /// options will be used.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ///
  /// [TInput] The type of input message.
  ///
  /// [TOutput] The type of output message.
  Executor(String id, {ExecutorOptions? options = null, bool? declareCrossRunShareable = null, });

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    var handlerDelegate = this.handleAsync;
    return protocolBuilder.configureRoutes((routeBuilder) => routeBuilder.addHandler(handlerDelegate))
                              .addMethodAttributeTypes(handlerDelegate.method)
                              .addClassAttributeTypes(this.runtimeType);
  }

  @override
  Future<TOutput> handle(
    TInput message,
    WorkflowContext context,
    {CancellationToken? cancellationToken, },
  );
}
/// Provides a simple executor implementation that uses a single message
/// handler function to process incoming messages.
///
/// [id] A unique identifier for the executor.
///
/// [options] Configuration options for the executor. If `null`, default
/// options will be used.
///
/// [declareCrossRunShareable] Declare that this executor may be used
/// simultaneously by multiple runs safely.
///
/// [TInput] The type of input message.
abstract class Executor<TInput> extends Executor implements MessageHandler<TInput> {
  /// Provides a simple executor implementation that uses a single message
  /// handler function to process incoming messages.
  ///
  /// [id] A unique identifier for the executor.
  ///
  /// [options] Configuration options for the executor. If `null`, default
  /// options will be used.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ///
  /// [TInput] The type of input message.
  Executor(String id, {ExecutorOptions? options = null, bool? declareCrossRunShareable = null, });

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    var handlerDelegate = this.handleAsync;
    return protocolBuilder.configureRoutes((routeBuilder) => routeBuilder.addHandler(handlerDelegate))
                              .addMethodAttributeTypes(handlerDelegate.method)
                              .addClassAttributeTypes(this.runtimeType);
  }

  @override
  Future handle(TInput message, WorkflowContext context, {CancellationToken? cancellationToken, });
}
class ExecutorProtocol {
  const ExecutorProtocol(
    MessageRouter router,
    Set<Type> sendTypes,
    Set<Type> yieldTypes,
  ) :
      router = router,
      _yieldTypes = yieldTypes;

  final Set<TypeId> _yieldTypes = new(yieldTypes.Select(type => TypeId(type)));

  final Map<Type, bool> _canOutputCache;

  MessageTypeTranslator get sendTypeTranslator {
    return field ??= messageTypeTranslator(sendTypes);
  }

  MessageRouter get router {
    return router;
  }

  bool canHandle(Type type) {
    return router.canHandle(type);
  }

  bool canOutput(Type type) {
    return this._canOutputCache.getOrAdd(type, this.canOutputCore);
  }

  bool canOutputCore(Type type) {
    for (final yieldType in this._yieldTypes) {
      if (yieldType.isMatchPolymorphic(type)) {
        return true;
      }
    }
    return false;
  }

  ProtocolDescriptor describe() {
    return new(this.router.incomingTypes, yieldTypes, sendTypes, this.router.hasCatchAll);
  }
}
class MessageTypeTranslator {
  MessageTypeTranslator(Set<Type> types) {
    for (final type in knownSentTypes + types) {
      var typeId = new(type);
      if (this._typeLookupMap.containsKey(typeId)) {
        continue;
      }
      this._typeLookupMap[typeId] = type;
      this._declaredTypeMap[type] = typeId;
    }
  }

  final Map<TypeId, Type> _typeLookupMap = {};

  final Map<Type, TypeId> _declaredTypeMap = {};

  static Iterable<Type> get knownSentTypes {
    return [
            ExternalRequest,
            ExternalResponse,

            // TurnToken?
        ];
  }

  TypeId? getDeclaredType(Type messageType) {
    for (var candidateType = messageType; candidateType != null; candidateType = candidateType.baseType) {
      TypeId? declaredTypeId;
      if (this._declaredTypeMap.containsKey(candidateType)) {
        if (candidateType != messageType) {
          // Add an entry for the derived type to speed up future lookups.
                    this._declaredTypeMap[messageType] = declaredTypeId;
        }
        return declaredTypeId;
      }
    }
    return null;
  }

  Type? mapTypeId(TypeId candidateTypeId) {
    return this._typeLookupMap.tryGetValue(candidateTypeId)
            ? mappedType
            : null;
  }
}
