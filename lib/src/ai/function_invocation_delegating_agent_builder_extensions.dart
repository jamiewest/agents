import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../abstractions/ai_agent.dart';
import '../func_typedefs.dart';
import 'ai_agent_builder.dart';
import 'function_invocation_delegating_agent.dart';

/// Provides extension methods for configuring and customizing
/// [AIAgentBuilder] instances.
extension FunctionInvocationDelegatingAgentBuilderExtensions on AIAgentBuilder {
  /// Adds a function invocation [callback] to the [AIAgent] pipeline that
  /// intercepts and processes [AIFunction] calls.
  ///
  /// The callback must call the provided continuation delegate to proceed with
  /// the function invocation, unless it intends to completely replace the
  /// function's behavior. The inner agent or the pipeline wrapping it must
  /// include a [FunctionInvokingChatClient]. If one does not exist, the
  /// [AIAgent] added to the pipeline by this method will throw an exception
  /// when invoked. Returns the [AIAgentBuilder] instance, enabling method
  /// chaining.
  AIAgentBuilder use(
    Func4<
      AIAgent,
      FunctionInvocationContext,
      Func2<FunctionInvocationContext, CancellationToken, Future<Object?>>,
      CancellationToken,
      Future<Object?>
    >
    callback,
  ) {
    return useFactory((innerAgent, _) {
      if (innerAgent.getService(FunctionInvokingChatClient) == null) {
        throw StateError(
          'The function invocation middleware can only be used with decorations of a AIAgent that support usage of FunctionInvokingChatClient decorated chat clients.',
        );
      }
      return FunctionInvocationDelegatingAgent(innerAgent, callback);
    });
  }
}
