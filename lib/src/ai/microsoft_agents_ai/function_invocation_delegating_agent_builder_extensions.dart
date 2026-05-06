import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import 'ai_agent_builder.dart';
import 'function_invocation_delegating_agent.dart';

/// Provides extension methods for configuring and customizing
/// [AIAgentBuilder] instances.
extension FunctionInvocationDelegatingAgentBuilderExtensions on AIAgentBuilder {
  /// Adds function invocation callbacks to the [AIAgent] pipeline that
/// intercepts and processes [AIFunction] calls.
///
/// Remarks: The callback must call the provided continuation delegate to
/// proceed with the function invocation, unless it intends to completely
/// replace the function's behavior. The inner agent or the pipeline wrapping
/// it must include a [FunctionInvokingChatClient]. If one does not exist, the
/// [AIAgent] added to the pipline by this method will throw an exception when
/// it is invoked.
///
/// Returns: The [AIAgentBuilder] instance with the function invocation
/// callback added, enabling method chaining.
///
/// [builder] The [AIAgentBuilder] to which the function invocation callback
/// is added.
///
/// [callback] A delegate that processes function invocations. The delegate
/// receives the [AIAgent] instance, the function invocation context, and a
/// continuation delegate representing the next callback in the pipeline. It
/// returns a task representing the result of the function invocation.
AIAgentBuilder use(Func4<AIAgent, FunctionInvocationContext, Func2<FunctionInvocationContext, CancellationToken, Future<Object?>>, CancellationToken, Future<Object?>> callback) {
return builder.use((innerAgent, _) {
        
            // Function calling requires a ChatClientAgent inner agent.
            if (innerAgent.getService<FunctionInvokingChatClient>() == null)
            {
                throw StateError('The function invocation middleware can only be used with decorations of a ${'AIAgent'} that support usage of FunctionInvokingChatClient decorated chat clients.');
            }

            return functionInvocationDelegatingAgent(innerAgent, callback);
        });
 }
 }
