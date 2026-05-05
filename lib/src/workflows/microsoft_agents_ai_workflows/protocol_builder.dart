import 'executor.dart';
import 'executor_options.dart';
import 'route_builder.dart';
import 'workflow_output_event.dart';
import '../../func_typedefs.dart';

extension MemberAttributeExtensions on MemberInfo {EnumerableTypeSentEnumerableTypeYielded getAttributeTypes() {
var sendsMessageAttrs = memberInfo.getCustomAttributes<SendsMessageAttribute>();
var yieldsOutputAttrs = memberInfo.getCustomAttributes<YieldsOutputAttribute>();
return (
  Sent: sendsMessageAttrs.map((attr) => attr.type),
  Yielded: yieldsOutputAttrs.map((attr) => attr.type),
);
 }
 }
/// .
class ProtocolBuilder {
  ProtocolBuilder(DelayedExternalRequestContext delayRequestContext) {
    this.routeBuilder = routeBuilder(delayRequestContext);
  }

  final Set<Type> _sendTypes = {};

  final Set<Type> _yieldTypes = {};

  /// Gets a route builder to configure message handlers.
  late final RouteBuilder routeBuilder;

  /// Adds types registered in [SendsMessageAttribute] or
  /// [YieldsOutputAttribute] on the target [Delegate]. This can be used to
  /// implement delegate-based request handling akin to what is provided by
  /// [Executor] or [Executor].
  ///
  /// Returns:
  ///
  /// [delegate] The delegate to be registered.
  ProtocolBuilder addDelegateAttributeTypes(Delegate delegate) {
    return this.addMethodAttributeTypes(delegate.method);
  }

  /// Adds types registered in [SendsMessageAttribute] or
  /// [YieldsOutputAttribute] on the target [MethodInfo]. This can be used to
  /// implement delegate-based request handling akin to what is provided by
  /// [Executor] or [Executor].
  ///
  /// Returns:
  ///
  /// [method] The method to be registered.
  ProtocolBuilder addMethodAttributeTypes(MethodInfo method) {
    (Iterable<Type> sentTypes, Iterable<Type> yieldTypes) = method.getAttributeTypes();
    this._sendTypes.addAll(sentTypes);
    this._yieldTypes.addAll(yieldTypes);
    return method.declaringType != null ? this.addClassAttributeTypes(method.declaringType)
                                            : this;
  }

  /// Adds types registered in [SendsMessageAttribute] or
  /// [YieldsOutputAttribute] on the target [Type]. This can be used to
  /// implement delegate-based request handling akin to what is provided by
  /// [Executor] or [Executor].
  ///
  /// Returns:
  ///
  /// [executorType] The type to be registered.
  ProtocolBuilder addClassAttributeTypes(Type executorType) {
    (Iterable<Type> sentTypes, Iterable<Type> yieldTypes) = executorType.getAttributeTypes();
    this._sendTypes.addAll(sentTypes);
    this._yieldTypes.addAll(yieldTypes);
    return this;
  }

  /// Adds the specified type to the set of declared "sent" message types for
  /// the protocol. Objects of these types will be allowed to be sent through
  /// the Executor's outgoing edges, via [CancellationToken)].
  ///
  /// Returns:
  ///
  /// [TMessage] The type to be declared.
  ProtocolBuilder sendsMessage<TMessage>() {
    return this.sendsMessageTypes([TMessage]);
  }

  /// Adds the specified type to the set of declared "sent" messagetypes for the
  /// protocol. Objects of these types will be allowed to be sent through the
  /// Executor's outgoing edges, via [CancellationToken)].
  ///
  /// Returns:
  ///
  /// [messageType] The type to be declared.
  ProtocolBuilder sendsMessageType(Type messageType) {
    return this.sendsMessageTypes([messageType]);
  }

  /// Adds the specified types to the set of declared "sent" message types for
  /// the protocol. Objects of these types will be allowed to be sent through
  /// the Executor's outgoing edges, via [CancellationToken)].
  ///
  /// Returns:
  ///
  /// [messageTypes] A set of types to be declared.
  ProtocolBuilder sendsMessageTypes(Iterable<Type> messageTypes) {
    this._sendTypes.addAll(messageTypes);
    return this;
  }

  /// Adds the specified output type to the set of declared "yielded" output
  /// types for the protocol. Objects of this type will be allowed to be output
  /// from the executor through the [WorkflowOutputEvent], via
  /// [CancellationToken)].
  ///
  /// Returns:
  ///
  /// [TOutput] The type to be declared.
  ProtocolBuilder yieldsOutput<TOutput>() {
    return this.yieldsOutputTypes([TOutput]);
  }

  /// Adds the specified output type to the set of declared "yielded" output
  /// types for the protocol. Objects of this type will be allowed to be output
  /// from the executor through the [WorkflowOutputEvent], via
  /// [CancellationToken)].
  ///
  /// Returns:
  ///
  /// [outputType] The type to be declared.
  ProtocolBuilder yieldsOutputType(Type outputType) {
    return this.yieldsOutputTypes([outputType]);
  }

  /// Adds the specified types to the set of declared "yielded" output types for
  /// the protocol. Objects of these types will be allowed to be output from the
  /// executor through the [WorkflowOutputEvent], via [CancellationToken)].
  ///
  /// Returns:
  ///
  /// [yieldedTypes] A set of types to be declared.
  ProtocolBuilder yieldsOutputTypes(Iterable<Type> yieldedTypes) {
    this._yieldTypes.addAll(yieldedTypes);
    return this;
  }

  /// Fluently configures message handlers.
  ///
  /// Returns:
  ///
  /// [configureAction] The handler configuration callback.
  ProtocolBuilder configureRoutes(Action<RouteBuilder> configureAction) {
    configureAction(this.routeBuilder);
    return this;
  }

  ExecutorProtocol build(ExecutorOptions options) {
    var router = this.routeBuilder.build();
    var sendTypes = new(this._sendTypes);
    if (options.autoSendMessageHandlerResultObject) {
      sendTypes.addAll(router.defaultOutputTypes);
    }
    var yieldTypes = new(this._yieldTypes);
    if (options.autoYieldOutputHandlerResultObject) {
      yieldTypes.addAll(router.defaultOutputTypes);
    }
    return new(router, sendTypes, yieldTypes);
  }
}
