import '../executor_options.dart';
import '../protocol_builder.dart';
import '../workflow.dart';

/// A component that processes messages in a [Workflow].
///
/// Remarks: This type is obsolete. Use the [MessageHandlerAttribute] on
/// methods in a partial class deriving from [Executor] instead.
///
/// [TExecutor] The actual type of the [ReflectingExecutor]. This is used to
/// reflectively discover handlers for messages without violating ILTrim
/// requirements.
class ReflectingExecutor<TExecutor> extends Executor {
  ReflectingExecutor(
    String id, {
    ExecutorOptions? options = null,
    bool? declareCrossRunShareable = null,
  });

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    protocolBuilder
        .sendsMessageTypes(
          TExecutor
              .getCustomAttributes<SendsMessageAttribute>(inherit: true)
              .map((attr) => attr.type),
        )
        .yieldsOutputTypes(
          TExecutor
              .getCustomAttributes<YieldsOutputAttribute>(inherit: true)
              .map((attr) => attr.type),
        );
    var messageHandlers = TExecutor.getHandlerInfos().toList();
    for (final handlerInfo in messageHandlers) {
      protocolBuilder.routeBuilder.addHandlerInternal(
        handlerInfo.inType,
        handlerInfo.bind(this, checkType: true),
        handlerInfo.outType,
      );
      if (handlerInfo.outType != null) {
        if (this.options.autoSendMessageHandlerResultObject) {
          protocolBuilder.sendsMessageType(handlerInfo.outType);
        }
        if (this.options.autoYieldOutputHandlerResultObject) {
          protocolBuilder.yieldsOutputType(handlerInfo.outType);
        }
      }
    }
    if (messageHandlers.length > 0) {
      var handlerAnnotatedTypes = messageHandlers
          .map(
            (mhi) => (
              SendTypes: mhi.handlerInfo
                  .getCustomAttributes<SendsMessageAttribute>()
                  .map((attr) => attr.type),
              YieldTypes: mhi.handlerInfo
                  .getCustomAttributes<YieldsOutputAttribute>()
                  .map((attr) => attr.type),
            ),
          )
          .aggregate(
            (accumulate, next) => (
              accumulate.sendTypes == null
                  ? next.sendTypes
                  : accumulate.sendTypes + next.sendTypes,
              accumulate.yieldTypes == null
                  ? next.yieldTypes
                  : accumulate.yieldTypes + next.yieldTypes,
            ),
          );
      protocolBuilder
          .sendsMessageTypes(handlerAnnotatedTypes.sendTypes)
          .yieldsOutputTypes(handlerAnnotatedTypes.yieldTypes);
    }
    return protocolBuilder;
  }
}
