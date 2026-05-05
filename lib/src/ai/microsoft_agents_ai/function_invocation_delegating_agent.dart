import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/delegating_ai_agent.dart';
import 'chat_client/chat_client_agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

/// Internal agent decorator that adds function invocation middleware logic.
class FunctionInvocationDelegatingAgent extends DelegatingAIAgent {
  FunctionInvocationDelegatingAgent(
    AIAgent innerAgent,
    Func4<AIAgent, FunctionInvocationContext, Func2<FunctionInvocationContext, CancellationToken, Future<Object?>>, CancellationToken, Future<Object?>> delegateFunc,
  ) : _delegateFunc = delegateFunc {
  }

  final Func4<AIAgent, FunctionInvocationContext, Func2<FunctionInvocationContext, CancellationToken, Future<Object?>>, CancellationToken, Future<Object?>> _delegateFunc;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, },
  ) {
    return this.innerAgent.runAsync(
      messages,
      session,
      this.agentRunOptionsWithFunctionMiddleware(options),
      cancellationToken,
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, },
  ) {
    return this.innerAgent.runStreamingAsync(
      messages,
      session,
      this.agentRunOptionsWithFunctionMiddleware(options),
      cancellationToken,
    );
  }

  AgentRunOptions? agentRunOptionsWithFunctionMiddleware(AgentRunOptions? options) {
    if (options == null || options.runtimeType == AgentRunOptions) {
      options = chatClientAgentRunOptions();
    }
    if (options is! ChatClientAgentRunOptions aco) {
      throw UnsupportedError('Function Invocation Middleware is only supported without options or with ${'ChatClientAgentRunOptions'}.');
    }
    var originalFactory = aco.chatClientFactory;
    aco.chatClientFactory = (chatClient) =>
        {
            var builder = chatClient.asBuilder();

            if (originalFactory != null)
            {
                builder.use(originalFactory);
      }

            return builder.configureOptions((co) => co.tools = co.tools?.map((tool) => tool is AIFunction aiFunction
                        ? middlewareEnabledFunction(this.innerAgent, aiFunction, this._delegateFunc)
                        : tool)
                    .toList())
                .build();
        };
    return options;
  }
}
class MiddlewareEnabledFunction extends DelegatingAIFunction {
  const MiddlewareEnabledFunction(
    AIAgent innerAgent,
    AIFunction innerFunction,
    Func4<AIAgent, FunctionInvocationContext, Func2<FunctionInvocationContext, CancellationToken, Future<Object?>>, CancellationToken, Future<Object?>> next,
  );

  @override
  Future<Object?> invokeCore(
    AIFunctionArguments arguments,
    CancellationToken cancellationToken,
  ) async  {
    var context = FunctionInvokingChatClient.currentContext
                ?? functionInvocationContext() // When there is no ambient context, create a new one to hold the arguments
                {
                    Arguments = arguments,
                    Function = this.innerFunction,
                    CallContent = new(
                      '',
                      this.innerFunction.name,
                      new Dictionary<String, Object?>(arguments),
                    ),
                };
    return await next(innerAgent, context, CoreLogicAsync, cancellationToken);
    /* TODO: unsupported node kind "unknown" */
    // ValueTask<Object?> CoreLogicAsync(FunctionInvocationContext ctx, CancellationToken cancellationToken)
    //                 => super.InvokeCoreAsync(ctx.Arguments, cancellationToken);
  }
}
