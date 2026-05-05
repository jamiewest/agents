import 'execution/call_result.dart';
import 'workflow_context.dart';

abstract class MessageRouter {
  Set<Type> get incomingTypes;
  bool canHandle({Object? message, Type? candidateType});
  Future<CallResult?> routeMessage(
    Object message,
    WorkflowContext context, {
    bool? requireRoute,
  });
}
