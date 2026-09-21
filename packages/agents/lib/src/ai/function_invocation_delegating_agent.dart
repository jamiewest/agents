import 'dart:collection';

import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../func_typedefs.dart';
import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_update.dart';
import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/delegating_ai_agent.dart';
import 'chat_client/chat_client_agent_run_options.dart';
import '../abstractions/ai_agent.dart';

/// Delegate type used to intercept and customise AI function invocations.
///
/// Receives the invoking [AIAgent], the [FunctionInvocationContext], the next
/// handler in the pipeline, and a [CancellationToken]. Must return the
/// function result.
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
    super.innerAgent,
    FunctionInvocationDelegateFunc delegateFunc,
  ) : _delegateFunc = delegateFunc;

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

  /// Decorates [options] so the middleware callback runs for every function
  /// invoked by this run.
  ///
  /// Works on a per-run copy so adding callback support does not change
  /// options the caller may reuse.
  ChatClientAgentRunOptions agentRunOptionsWithFunctionMiddleware(
    AgentRunOptions? options,
  ) {
    if (options == null || options.runtimeType == AgentRunOptions) {
      // Plain agent options cannot hold a chat-client factory, so copy their
      // shared values to chat-specific options.
      final copied = ChatClientAgentRunOptions();
      if (options != null) {
        copied
          ..responseFormat = options.responseFormat
          ..continuationToken = options.continuationToken
          ..allowBackgroundResponses = options.allowBackgroundResponses
          ..additionalProperties = options.additionalProperties;
      }
      options = copied;
    } else if (options is ChatClientAgentRunOptions) {
      options = options.clone() as ChatClientAgentRunOptions;
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
            (messages, opts, innerClient, token) => innerClient.getResponse(
              messages: messages,
              options: _withMiddlewareTools(opts, agent, delegateFunc),
              cancellationToken: token,
            ),
            (messages, opts, innerClient, token) =>
                innerClient.getStreamingResponse(
                  messages: messages,
                  options: _withMiddlewareTools(opts, agent, delegateFunc),
                  cancellationToken: token,
                ),
          )
          .build();
    };
    return aco;
  }

  /// Returns per-request options whose tool list wraps every [AIFunction] in
  /// the middleware callback, leaving the caller-owned [opts] unchanged.
  static ChatOptions? _withMiddlewareTools(
    ChatOptions? opts,
    AIAgent agent,
    FunctionInvocationDelegateFunc delegateFunc,
  ) {
    final tools = opts?.tools;
    if (opts == null || tools == null) {
      return opts;
    }

    // Each request gets its own options object; `clone` copies the tool list
    // into a plain list, which is then replaced by the wrapping collection.
    final cloned = opts.clone();
    cloned.tools = MiddlewareEnabledTools(tools, agent, delegateFunc);
    return cloned;
  }
}

/// A tool list that wraps every [AIFunction] it holds — including ones added
/// or replaced later in the same run — in a [MiddlewareEnabledFunction].
class MiddlewareEnabledTools extends ListBase<AITool> {
  /// Creates a list seeded from [tools], wrapping each entry.
  MiddlewareEnabledTools(
    Iterable<AITool> tools,
    this.agent,
    this.delegateFunc,
  ) {
    // `addAll` wraps the functions already present, just as it wraps
    // functions added later.
    addAll(tools);
  }

  /// The agent passed to the middleware callback.
  final AIAgent agent;

  /// The middleware callback applied to each function.
  final FunctionInvocationDelegateFunc delegateFunc;

  final List<AITool> _tools = [];

  @override
  int get length => _tools.length;

  @override
  set length(int newLength) => _tools.length = newLength;

  @override
  AITool operator [](int index) => _tools[index];

  @override
  void operator []=(int index, AITool value) => _tools[index] = _wrap(value);

  @override
  void add(AITool element) => _tools.add(_wrap(element));

  @override
  void addAll(Iterable<AITool> iterable) {
    for (final tool in iterable) {
      _tools.add(_wrap(tool));
    }
  }

  @override
  void insert(int index, AITool element) =>
      _tools.insert(index, _wrap(element));

  @override
  void insertAll(int index, Iterable<AITool> iterable) =>
      _tools.insertAll(index, iterable.map(_wrap));

  AITool _wrap(AITool tool) => tool is AIFunction
      ? MiddlewareEnabledFunction.wrap(tool, agent, delegateFunc)
      : tool;
}

/// Wraps an [AIFunction] to inject middleware logic on invocation.
class MiddlewareEnabledFunction extends DelegatingAIFunction {
  /// Wraps [innerFunction] so [next] runs around each invocation.
  MiddlewareEnabledFunction(
    this.innerAgent,
    AIFunction innerFunction,
    this.next,
  ) : super(innerFunction);

  /// Wraps [function] unless it already carries this exact callback.
  ///
  /// Wrapping is idempotent so repeated requests in one run — or a tool list
  /// that is rebuilt mid-run — do not stack a callback on itself.
  static AIFunction wrap(
    AIFunction function,
    AIAgent agent,
    FunctionInvocationDelegateFunc next,
  ) {
    AIFunction current = function;
    while (current is DelegatingAIFunction) {
      if (current is MiddlewareEnabledFunction &&
          identical(current.next, next) &&
          identical(current.innerAgent, agent)) {
        return function;
      }
      current = current.innerFunction;
    }
    return MiddlewareEnabledFunction(agent, function, next);
  }

  /// The agent passed to the middleware callback.
  final AIAgent innerAgent;

  /// The middleware callback invoked around the inner function.
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
