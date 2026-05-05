import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'protocol_builder.dart';
import 'resettable_executor.dart';
import 'turn_token.dart';
import 'workflow_context.dart';

/// A ChatProtocol executor that forwards all messages it receives. Useful for
/// splitting inputs into parallel processing paths.
///
/// Remarks: This executor is designed to be cross-run shareable and can be
/// reset to its initial state. It handles multiple chat-related types,
/// enabling flexible message forwarding scenarios. Thread safety and
/// reusability are ensured by its design.
///
/// [id] The unique identifier for the executor instance. Used to distinguish
/// this executor within the system.
///
/// [options] Optional configuration settings for the executor. If null,
/// default options are used.
class ChatForwardingExecutor extends Executor implements ResettableExecutor {
  /// A ChatProtocol executor that forwards all messages it receives. Useful for
  /// splitting inputs into parallel processing paths.
  ///
  /// Remarks: This executor is designed to be cross-run shareable and can be
  /// reset to its initial state. It handles multiple chat-related types,
  /// enabling flexible message forwarding scenarios. Thread safety and
  /// reusability are ensured by its design.
  ///
  /// [id] The unique identifier for the executor instance. Used to distinguish
  /// this executor within the system.
  ///
  /// [options] Optional configuration settings for the executor. If null,
  /// default options are used.
  ChatForwardingExecutor(String id, {ChatForwardingExecutorOptions? options = null, });

  final ChatRole? _stringMessageChatRole = options?.StringMessageChatRole;

  @override
  ProtocolBuilder configureProtocol(ProtocolBuilder protocolBuilder) {
    return protocolBuilder.configureRoutes(ConfigureRoutes)
                              .sendsMessage<ChatMessage>()
                              .sendsMessage<List<ChatMessage>>()
                              .sendsMessage<ChatMessage[]>()
                              .sendsMessage<TurnToken>();
    /* TODO: unsupported node kind "unknown" */
    // void ConfigureRoutes(RouteBuilder routeBuilder)
    //         {
      //             if (this._stringMessageChatRole.HasValue)
      //             {
        //                 routeBuilder = routeBuilder.AddHandler<String>(
        //                     (message, context) => context.SendMessageAsync(new ChatMessage(this._stringMessageChatRole.Value, message)));
        //             }
      //
      //             routeBuilder.AddHandler<ChatMessage>(ForwardMessageAsync)
      //                         .AddHandler<Iterable<ChatMessage>>(ForwardMessagesAsync)
      //                         // remove this once we internalize the typecheck logic
      //                         .AddHandler<ChatMessage[]>(ForwardMessagesAsync)
      //                         //.AddHandler<List<ChatMessage>>(ForwardMessagesAsync)
      //                         .AddHandler<TurnToken>(ForwardTurnTokenAsync);
      //         }
  }

  static Future forwardMessage(
    ChatMessage message,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    return context.sendMessage(message, cancellationToken);
  }

  static Future forwardTurnToken(
    TurnToken message,
    WorkflowContext context,
    CancellationToken cancellationToken,
  ) {
    return context.sendMessage(message, cancellationToken);
  }

  static Future forwardMessages(
    WorkflowContext context,
    CancellationToken cancellationToken,
    {Iterable<ChatMessage>? messages, },
  ) {
    return context.sendMessage(
      messages is List<ChatMessage> messageList ? messageList : messages.toList(),
      cancellationToken,
    );
  }

  @override
  Future reset() {
    return Future.value(null);
  }
}
/// Provides configuration options for [ChatForwardingExecutor].
class ChatForwardingExecutorOptions {
  ChatForwardingExecutorOptions();

  /// Gets or sets the chat role to use when converting String messages to
  /// [ChatMessage] instances. If set, the executor will accept String messages
  /// and convert them to chat messages with this role.
  ChatRole? stringMessageChatRole;

}
