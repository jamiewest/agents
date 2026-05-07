import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../func_typedefs.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/delegating_ai_agent.dart';
import 'chat_client/chat_client_agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

typedef FunctionInvocationDelegateFunc =
    Func4<
      AIAgent,
      FunctionInvocationContext,
      Func2<FunctionInvocationContext, CancellationToken, Future<Object?>>,
      CancellationToken,
      Future<Object?>
    >;

/// Internal agent decorator that adds function invocation middleware logic.
class FunctionInvocationDelegatingAgent extends DelegatingAIAgent {
  FunctionInvocationDelegatingAgent(
    AIAgent innerAgent,
    FunctionInvocationDelegateFunc delegateFunc,
  ) : _delegateFunc = delegateFunc,
      super(innerAgent);

  final FunctionInvocationDelegateFunc _delegateFunc;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return innerAgent.runCore(
      messages,
      session: session,
      options: agentRunOptionsWithFunctionMiddleware(options),
      cancellationToken: cancellationToken,
    );
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    return innerAgent.runCoreStreaming(
      messages,
      session: session,
      options: agentRunOptionsWithFunctionMiddleware(options),
      cancellationToken: cancellationToken,
    );
  }

  AgentRunOptions? agentRunOptionsWithFunctionMiddleware(
    AgentRunOptions? options,
  ) {
    if (options == null || options.runtimeType == AgentRunOptions) {
      options = ChatClientAgentRunOptions();
    }
    if (options is! ChatClientAgentRunOptions) {
      throw UnsupportedError(
        'Function Invocation Middleware is only supported without options or '
        'with ChatClientAgentRunOptions.',
      );
    }
    final aco = options;
    final originalFactory = aco.chatClientFactory;
    final delegateFunc = _delegateFunc;
    final agent = innerAgent;
    aco.chatClientFactory = (chatClient) {
      var builder = ChatClientBuilder(chatClient);
      if (originalFactory != null) {
        builder.use(originalFactory);
      }
      return builder
          .useDelegates(
            (messages, opts, innerClient, token) {
              _wrapTools(opts, agent, delegateFunc);
              return innerClient.getResponse(
                messages: messages,
                options: opts,
                cancellationToken: token,
              );
            },
            (messages, opts, innerClient, token) {
              _wrapTools(opts, agent, delegateFunc);
              return innerClient.getStreamingResponse(
                messages: messages,
                options: opts,
                cancellationToken: token,
              );
            },
          )
          .build();
    };
    return options;
  }

  static void _wrapTools(
    ChatOptions? opts,
    AIAgent agent,
    FunctionInvocationDelegateFunc delegateFunc,
  ) {
    if (opts?.tools == null) return;
    opts!.tools = opts.tools!
        .map(
          (tool) => tool is AIFunction
              ? MiddlewareEnabledFunction(agent, tool, delegateFunc)
              : tool,
        )
        .toList();
  }
}

/// Wraps an [AIFunction] to inject middleware logic on invocation.
class MiddlewareEnabledFunction extends DelegatingAIFunction {
  MiddlewareEnabledFunction(
    this.innerAgent,
    AIFunction innerFunction,
    this.next,
  ) : super(innerFunction);

  final AIAgent innerAgent;
  final FunctionInvocationDelegateFunc next;

  @override
  Future<Object?> invokeCore(
    AIFunctionArguments arguments, {
    CancellationToken? cancellationToken,
  }) async {
    final callContent = FunctionCallContent(
      callId: '',
      name: innerFunction.name,
      arguments: Map<String, Object?>.from(arguments),
    );
    final ctx = FunctionInvocationContext(
      message: ChatMessage(role: ChatRole.assistant, contents: [callContent]),
      callContent: callContent,
      function_: innerFunction,
      iteration: 0,
      functionCallIndex: 0,
      functionCount: 1,
    );
    return await next(
      innerAgent,
      ctx,
      _coreLogicAsync,
      cancellationToken ?? CancellationToken.none,
    );
  }

  Future<Object?> _coreLogicAsync(
    FunctionInvocationContext ctx,
    CancellationToken cancellationToken,
  ) => super.invokeCore(
    AIFunctionArguments(ctx.callContent.arguments ?? {}),
    cancellationToken: cancellationToken,
  );
}
