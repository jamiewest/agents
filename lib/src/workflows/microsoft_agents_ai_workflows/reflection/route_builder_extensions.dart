import 'message_handler_info.dart';

extension MessageHandlerReflection on Type {MethodInfo reflectHandle(int genericArgumentCount) {
assert(specializedType.isGenericType &&
                     (specializedType.getGenericTypeDefinition() == IMessageHandler<> ||
                      specializedType.getGenericTypeDefinition() == IMessageHandler<var>),
            "specializedType must be an IMessageHandler<> or IMessageHandler<var> type.");
return genericArgumentCount switch
        {
            1 => specializedType.getMethodFromGenericMethodDefinition(HandleAsync_1),
            2 => specializedType.getMethodFromGenericMethodDefinition(HandleAsync_2),
            (_) => throw ArgumentError.value('genericArgumentCount', "Must be 1 or 2.")
        };
 }
int genericArgumentCount() {
assert(
  type.isMessageHandlerType(),
  "type must be an IMessageHandler<> or IMessageHandler<var> type.",
);
return type.getGenericArguments().length;
 }
bool isMessageHandlerType() {
return type.isGenericType &&
        (type.getGenericTypeDefinition() == IMessageHandler<> ||
         type.getGenericTypeDefinition() == IMessageHandler<var>);
 }
 }
extension RouteBuilderExtensions on Type {Iterable<MessageHandlerInfo> getHandlerInfos() {
// Handlers are defined by implementations of IMessageHandler<TMessage> or IMessageHandler<TMessage, TResult>
        assert(
          Executor.isAssignableFrom(executorType),
          "executorType must be an Executor type.",
        );
for (final interfaceType in executorType.getInterfaces()) {
  if (!interfaceType.isMessageHandlerType()) {
    continue;
  }

  var genericArguments = interfaceType.getGenericArguments();
  if (genericArguments.length < 1 || genericArguments.length > 2) {
    continue;
  }

  var inType = genericArguments[0];
  var outType = genericArguments.length == 2 ? genericArguments[1] : null;
  var method = interfaceType.reflectHandle(genericArguments.length);
  if (method != null) {
    yield messageHandlerInfo(method);
  }
}
 }
 }
