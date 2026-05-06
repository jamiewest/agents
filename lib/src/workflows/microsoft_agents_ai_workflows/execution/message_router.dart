import 'package:extensions/system.dart';
import '../../../func_typedefs.dart';
import '../checkpointing/type_id.dart';
import '../portable_value.dart';
import '../workflow_context.dart';
import 'call_result.dart';

class MessageRouter {
  MessageRouter(
    Map<Type, Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>>> handlers,
    Set<Type> outputTypes,
    Func3<PortableValue, WorkflowContext, CancellationToken, Future<CallResult>>? catchAllFunc,
  ) : _catchAllFunc = catchAllFunc {
    var interfaceHandlers = new();
    for (final type in handlers.keys) {
      this._typeInfos[new(type)] = new(type, handlers[type]);
      if (type.isInterface) {
        interfaceHandlers.add(type);
      }
    }
    this._interfaceHandlers = interfaceHandlers.toList();
    this.incomingTypes = [...handlers.keys];
    this.defaultOutputTypes = outputTypes;
  }

  late final List<Type> _interfaceHandlers;

  final Map<TypeId, TypeHandlingInfo> _typeInfos;

  final Func3<PortableValue, WorkflowContext, CancellationToken, Future<CallResult>>? _catchAllFunc;

  late final Set<Type> incomingTypes;

  late final Set<Type> defaultOutputTypes;

  bool get hasCatchAll {
    return this._catchAllFunc != null;
  }

  bool canHandle({Object? message, Type? candidateType, }) {
    return this.canHandle(message.runtimeType);
  }

  Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>>? findHandler(Type messageType) {
    for (var candidateType = messageType; candidateType != null; candidateType = candidateType.baseType) {
      var candidateTypeId = new(candidateType);
      TypeHandlingInfo handlingInfo;
      if (this._typeInfos.containsKey(candidateTypeId)) {
        if (candidateType != messageType) {
          var actualInfo = handlingInfo.forDerviedType(messageType);
          this._typeInfos.tryAdd(new(messageType), actualInfo);
        }
        return handlingInfo.handler;
      } else if (this._interfaceHandlers.length > 0) {
        for (final interfaceType in this._interfaceHandlers.where((it) => it.isAssignableFrom(candidateType))) {
          handlingInfo = this._typeInfos[new(interfaceType)];
          // By definition we do not have a pre-calculated handler information for this candidateType, otherwise
                    // we would have found it above. This also means we do not have a corresponding entry for the messageType.
                    this._typeInfos.tryAdd(
                      new(messageType),
                      handlingInfo.forDerviedType(messageType),
                    );
          return handlingInfo.handler;
        }
      }
    }
    return null;
  }

  Future<CallResult?> routeMessage(
    Object message,
    WorkflowContext context,
    {bool? requireRoute, CancellationToken? cancellationToken, }
  ) async {
    var result = null;
    var PortableValue = message as PortableValue;
    TypeHandlingInfo handlingInfo;
    if (PortableValue != null &&
            this._typeInfos.containsKey(PortableValue.typeId)) {
      // If we found a runtime type, we can use it
            message = PortableValue.asType(handlingInfo.runtimeType) ?? message;
    }
    try {
      var handler = this.findHandler(message.runtimeType);
      if (handler != null) {
        result = await handler(message, context, cancellationToken);
      } else if (this.hasCatchAll) {
        PortableValue ??= PortableValue(message);
        result = await this._catchAllFunc(
          PortableValue,
          context,
          cancellationToken,
        ) ;
      }
    } catch (e, s) {
      if (e is Exception) {
        final e = e as Exception;
        {
          result = CallResult.raisedException(wasVoid: true, e);
        }
      } else {
        rethrow;
      }
    }
    return result;
  }
}
class TypeHandlingInfo {
  const TypeHandlingInfo(
    Type RuntimeType,
    Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>> Handler,
  ) :
      runtimeType = RuntimeType,
      handler = Handler;

  Type runtimeType;

  Func3<Object, WorkflowContext, CancellationToken, Future<CallResult>> handler;

  void assertTypeCovaraince(Type expectedDerviedType) {
    assert(this.runtimeType.isAssignableFrom(expectedDerviedType));
  }

  TypeHandlingInfo forDerviedType(Type derivedType) {
    this.assertTypeCovaraince(derivedType);
    return this with { runtimeType = derivedType };
  }

  @override
  bool operator ==(Object other) { if (identical(this, other)) return true;
    return other is TypeHandlingInfo &&
    runtimeType == other.runtimeType &&
    handler == other.handler; }
  @override
  int get hashCode { return Object.hash(runtimeType, handler); }
}
