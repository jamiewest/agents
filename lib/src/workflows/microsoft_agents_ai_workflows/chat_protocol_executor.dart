import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import '../../func_typedefs.dart';
import 'protocol_builder.dart';
import 'stateful_executor_options.dart';
import 'turn_token.dart';
import 'workflow_context.dart';

/// Provides a base class for executors that implement the Agent Workflow Chat
/// Protocol. This executor maintains a list of chat messages and processes
/// them when a turn is taken.
abstract class ChatProtocolExecutor extends StatefulExecutor<List<ChatMessage>> {
  /// Initializes a new instance of the [ChatProtocolExecutor] class.
  ///
  /// [id] The unique identifier for this executor instance. Cannot be null or
  /// empty.
  ///
  /// [options] Optional configuration settings for the executor. If null,
  /// default options are used.
  ///
  /// [declareCrossRunShareable] Declare that this executor may be used
  /// simultaneously by multiple runs safely.
  ChatProtocolExecutor(
    String id,
    {ChatProtocolExecutorOptions? options, bool? declareCrossRunShareable}
  ) {
    this._options = options ?? ChatProtocolExecutorOptions();
  }

  static final List<ChatMessage> Function() s_initFunction = () => [];

  late final ChatProtocolExecutorOptions _options;

  static final StatefulExecutorOptions s_baseExecutorOptions;

  /// Gets a value indicating whether String-based messages are supported by
  /// this [ChatProtocolExecutor].
  bool get supportsStringMessage {
    return this.stringMessageChatRole != null;
  }

  ChatRole? get stringMessageChatRole {
    return this._options.stringMessageChatRole;
  }

  bool get autoSendTurnToken {
    return this._options.autoSendTurnToken;
  }

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return protocolBuilder.configureRoutes(ConfigureRoutes)
                              .sendsMessage<List<ChatMessage>>()
                              .sendsMessage<TurnToken>();
    /* TODO: unsupported node kind "unknown" */
    // void ConfigureRoutes(RouteBuilder routeBuilder)
    //         {
      //             if (this.SupportsStringMessage)
      //             {
        //                 routeBuilder = routeBuilder.AddHandler<String>(
        //                     (message, context) => this.AddMessageAsync(new(this.StringMessageChatRole.Value, message), context));
        //             }
      //
      //             routeBuilder.AddHandler<ChatMessage>(this.AddMessageAsync)
      //                         .AddHandler<Iterable<ChatMessage>>(this.AddMessagesAsync)
      //                         .AddHandler<ChatMessage[]>(this.AddMessagesAsync)
      //                         //.AddHandler<List<ChatMessage>>(this.AddMessagesAsync)
      //                         .AddHandler<TurnToken>(this.TakeTurnAsync);
      //         }
  }

  /// Adds a single chat message to the accumulated messages for the current
  /// turn.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [message] The chat message to add.
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future addMessage(
    ChatMessage message,
    WorkflowContext context,
    {CancellationToken? cancellationToken, }
  ) {
    return this.invokeWithState(
      ForwardMessageAsync,
      context,
      cancellationToken: cancellationToken,
    );
    /* TODO: unsupported node kind "unknown" */
    // ValueTask<List<ChatMessage>?> ForwardMessageAsync(List<ChatMessage>? maybePendingMessages, IWorkflowContext context, CancellationToken cancelationToken)
    //         {
      //             maybePendingMessages ??= s_initFunction();
      //             maybePendingMessages.Add(message);
      //             return new(maybePendingMessages);
      //         }
  }

  /// Adds multiple chat messages to the accumulated messages for the current
  /// turn.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [messages] The collection of chat messages to add.
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future addMessages(
    Iterable<ChatMessage> messages,
    WorkflowContext context,
    {CancellationToken? cancellationToken, }
  ) {
    return this.invokeWithState(
      ForwardMessageAsync,
      context,
      cancellationToken: cancellationToken,
    );
    /* TODO: unsupported node kind "unknown" */
    // ValueTask<List<ChatMessage>?> ForwardMessageAsync(List<ChatMessage>? maybePendingMessages, IWorkflowContext context, CancellationToken cancelationToken)
    //         {
      //             maybePendingMessages ??= s_initFunction();
      //             maybePendingMessages.AddRange(messages);
      //             return new(maybePendingMessages);
      //         }
  }

  /// Handles a turn token by processing all accumulated chat messages and then
  /// resetting the message state.
  ///
  /// Returns: A [ValueTask] representing the asynchronous operation.
  ///
  /// [token] The turn token that triggers message processing.
  ///
  /// [context] The workflow context in which the executor executes.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  Future takeTurn(
    WorkflowContext context,
    CancellationToken cancellationToken,
    {TurnToken? token, List<ChatMessage>? messages, bool? emitEvents, }
  ) {
    return this.invokeWithState(
      InvokeTakeTurnAsync,
      context,
      cancellationToken: cancellationToken,
    );
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<List<ChatMessage>?> InvokeTakeTurnAsync(List<ChatMessage>? maybePendingMessages, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             await this.TakeTurnAsync(maybePendingMessages ?? s_initFunction(), context, token.EmitEvents, cancellationToken)
      //                       ;
      //
      //             if (this.AutoSendTurnToken)
      //             {
        //                 await context.SendMessageAsync(token, cancellationToken: cancellationToken);
        //             }
      //
      //             // Rerun the initialStateFactory to reset the state to empty list. (We could return the empty list directly,
      //             // but this is more consistent if the initial state factory becomes more complex.)
      //             return s_initFunction();
      //         }
  }

  /// Processes the current set of turn messages using the specified
  /// asynchronous processing function.
  ///
  /// Remarks: If the provided list of chat messages is null, an initial empty
  /// list is supplied to the processing function. If the processing function
  /// returns null, an empty list is used as the result.
  ///
  /// Returns: A ValueTask that represents the asynchronous operation. The
  /// result contains the processed list of chat messages, or an empty list if
  /// the processing function returns null.
  ///
  /// [processFunc] A delegate that asynchronously processes a list of chat
  /// messages within the given workflow context and cancellation token,
  /// returning the processed list of chat messages or null.
  ///
  /// [context] The workflow context in which the messages are processed.
  ///
  /// [cancellationToken] A token that can be used to cancel the asynchronous
  /// operation.
  Future processTurnMessages(
    Func3<List<ChatMessage>, WorkflowContext, CancellationToken, Future<List<ChatMessage>?>> processFunc,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    return this.invokeWithState(
      InvokeProcessFuncAsync,
      context,
      cancellationToken: cancellationToken,
    );
    /* TODO: unsupported node kind "unknown" */
    // async ValueTask<List<ChatMessage>?> InvokeProcessFuncAsync(List<ChatMessage>? maybePendingMessages, IWorkflowContext context, CancellationToken cancellationToken)
    //         {
      //             return (await processFunc(maybePendingMessages ?? s_initFunction(), context, cancellationToken))
      //                 ?? s_initFunction();
      //         }
  }
}
/// Provides configuration options for [ChatProtocolExecutor].
class ChatProtocolExecutorOptions {
  ChatProtocolExecutorOptions();

  /// Gets or sets the chat role to use when converting String messages to
  /// [ChatMessage] instances. If set, the executor will accept String messages
  /// and convert them to chat messages with this role.
  ChatRole? stringMessageChatRole;

  /// Gets or sets a value indicating whether the executor should automatically
  /// send the [TurnToken] after returning from [CancellationToken)]
  bool autoSendTurnToken = true;

}
