import '../../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';
import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_request_message_source_attribution.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/agent_request_message_source_type.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/ai_context_provider.dart';
import '../../../abstractions/microsoft_agents_ai_abstractions/provider_session_state_t_state_.dart';
import '../agent_json_utilities.dart';
import '../ai_agent_builder.dart';
import '../chat_client/chat_client_agent_session.dart';
import 'compaction_message_group.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_telemetry.dart';

/// A [AIContextProvider] that applies a [CompactionStrategy] to compact the
/// message list before each agent invocation.
///
/// Remarks: This provider performs in-run compaction by organizing messages
/// into atomic groups (preserving tool-call/result pairings) before applying
/// compaction logic. Only included messages are forwarded to the agent's
/// underlying chat client. The [CompactionProvider] can be added to an
/// agent's context provider pipeline via [AIContextProviders] or via
/// `UseAIContextProviders` on a [ChatClientBuilder] or [AIAgentBuilder].
class CompactionProvider extends AIContextProvider {
  /// Initializes a new instance of the [CompactionProvider] class.
  ///
  /// [compactionStrategy] The compaction strategy to apply before each
  /// invocation.
  ///
  /// [stateKey] An optional key used to store the provider state in the
  /// [StateBag]. Provide an explicit value if configuring multiple agents with
  /// different compaction strategies that will interact in the same session.
  ///
  /// [loggerFactory] An optional [LoggerFactory] used to create a logger for
  /// provider diagnostics. When `null`, logging is disabled.
  CompactionProvider(
    CompactionStrategy compactionStrategy,
    {String? stateKey = null, LoggerFactory? loggerFactory = null, },
  ) : _compactionStrategy = compactionStrategy {
    stateKey ??= this._compactionStrategy.runtimeType.toString();
    this.stateKeys = [stateKey];
    this._sessionState = ProviderSessionState<State>(
            (_) => State(),
            stateKey,
            AgentJsonUtilities.defaultOptions);
    this._loggerFactory = loggerFactory;
  }

  final CompactionStrategy _compactionStrategy;

  late final ProviderSessionState<State> _sessionState;

  late final LoggerFactory? _loggerFactory;

  late final List<String> stateKeys;

  /// Applies compaction strategy to the provided message list and returns the
  /// compacted messages. This can be used for ad-hoc compaction outside of the
  /// provider pipeline.
  ///
  /// Returns: An enumeration of the compacted [ChatMessage] instances.
  ///
  /// [compactionStrategy] The compaction strategy to apply before each
  /// invocation.
  ///
  /// [messages] The messages to compact
  ///
  /// [logger] An optional [Logger] for emitting compaction diagnostics.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  static Future<Iterable<ChatMessage>> compact(
    CompactionStrategy compactionStrategy,
    Iterable<ChatMessage> messages,
    {Logger? logger, CancellationToken? cancellationToken, },
  ) async  {
    var messageList = messages as List<ChatMessage> ?? [.. messages];
    var messageIndex = CompactionMessageIndex.create(messageList);
    await compactionStrategy.compactAsync(
      messageIndex,
      logger,
      cancellationToken,
    ) ;
    return messageIndex.getIncludedMessages();
  }

  /// Applies the compaction strategy to the accumulated message list before
  /// forwarding it to the agent.
  ///
  /// Returns: A task that represents the asynchronous operation. The task
  /// result contains an [AIContext] with the compacted message list.
  ///
  /// [context] Contains the request context including all accumulated messages.
  ///
  /// [cancellationToken] The [CancellationToken] to monitor for cancellation
  /// requests.
  @override
  Future<AIContext> invokingCore(
    InvokingContext context,
    {CancellationToken? cancellationToken, },
  ) async  {
    var activity = CompactionTelemetry.activitySource.startActivity(CompactionTelemetry.activityNames.compactionProviderInvoke);
    var loggerFactory = this.getLoggerFactory(context.agent);
    var logger = loggerFactory.createLogger<CompactionProvider>();
    var session = context.session;
    var allMessages = context.aiContext.messages;
    if (session == null|| allMessages == null) {
      logger.logCompactionProviderSkipped("no session or no messages");
      return context.aiContext;
    }
    var chatClientSession = session.getService<ChatClientAgentSession>();
    if (chatClientSession != null &&
            !(chatClientSession.conversationId == null || chatClientSession.conversationId.trim().isEmpty)) {
      logger.logCompactionProviderSkipped("session managed by remote service");
      return context.aiContext;
    }
    var messageList = allMessages as List<ChatMessage> ?? [.. allMessages];
    var state = this._sessionState.getOrInitializeState(session);
    CompactionMessageIndex messageIndex;
    if (state.messageGroups.length > 0) {
      messageIndex = new([.. state.messageGroups]);
      for (final message in messageIndex.groups.expand((x) => x.messages)) {
        message.additionalProperties ??= additionalPropertiesDictionary();
        message.additionalProperties[AgentRequestMessageSourceAttribution.additionalPropertiesKey] =
                    agentRequestMessageSourceAttribution(
                      AgentRequestMessageSourceType.chatHistory,
                      this.runtimeType.fullName!,
                    );
      }
      // Update existing index with any new messages appended since the last call.
            messageIndex.update(messageList);
    } else {
      // First pass — initialize the message index from scratch.
            messageIndex = CompactionMessageIndex.create(messageList);
    }
    var strategyName = this._compactionStrategy.runtimeType.toString();
    var beforeMessages = messageIndex.includedMessageCount;
    logger.logCompactionProviderApplying(beforeMessages, strategyName);
    // Apply compaction
        await this._compactionStrategy.compactAsync(
            messageIndex,
            loggerFactory.createLogger(this._compactionStrategy.runtimeType),
            cancellationToken);
    var afterMessages = messageIndex.includedMessageCount;
    if (afterMessages < beforeMessages) {
      logger.logCompactionProviderApplied(beforeMessages, afterMessages);
    }
    // Persist the index
        state.messageGroups.clear();
    state.messageGroups.addAll(messageIndex.groups);
    for (final message in messageIndex.groups.expand((x) => x.messages)) {
      if (message.getAgentRequestMessageSourceType() != AgentRequestMessageSourceType.chatHistory && !messageList.any((x) => x.contentEquals(message))) {
        message.additionalProperties ??= additionalPropertiesDictionary();
        message.additionalProperties[AgentRequestMessageSourceAttribution.additionalPropertiesKey] =
                    agentRequestMessageSourceAttribution(
                      AgentRequestMessageSourceType.chatHistory,
                      this.runtimeType.fullName!,
                    );
      }
    }
    return AIContext();
  }

  LoggerFactory getLoggerFactory(AIAgent agent) {
    return this._loggerFactory ??
        agent.getService<IChatClient>()?.getService<LoggerFactory>() ??
        NullLoggerFactory.instance;
  }
}
/// Represents the persisted state of a [CompactionProvider] stored in the
/// [StateBag].
class State {
  State();

  /// Gets or sets the message index groups used for incremental compaction
  /// updates.
  List<CompactionMessageGroup> messageGroups = [];

}
