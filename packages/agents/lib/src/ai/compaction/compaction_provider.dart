import 'package:extensions/ai.dart';
import 'package:extensions/logging.dart';
import 'package:extensions/system.dart';

import '../../abstractions/agent_request_message_source_type.dart';
import '../../abstractions/ai_agent.dart';
import '../../abstractions/ai_context.dart';
import '../../abstractions/ai_context_provider.dart';
import '../../abstractions/chat_message_extensions.dart';
import '../../abstractions/provider_session_state_t_state_.dart';
import '../agent_json_utilities.dart';
import '../chat_client/chat_client_agent_session.dart';
import 'chat_message_content_equality.dart';
import 'compaction_log_messages.dart';
import 'compaction_message_group.dart';
import 'compaction_message_index.dart';
import 'compaction_strategy.dart';
import 'compaction_telemetry.dart';

/// A [AIContextProvider] that applies a [CompactionStrategy] to compact the
/// message list before each agent invocation.
class CompactionProvider extends AIContextProvider {
  CompactionProvider(
    CompactionStrategy compactionStrategy, {
    String? stateKey,
    LoggerFactory? loggerFactory,
  }) : _compactionStrategy = compactionStrategy,
       _loggerFactory = loggerFactory {
    final resolvedStateKey =
        stateKey ?? compactionStrategy.runtimeType.toString();
    _stateKeys = [resolvedStateKey];
    _sessionState = ProviderSessionState<State>(
      (_) => State(),
      resolvedStateKey,
      JsonSerializerOptions: AgentJsonUtilities.defaultOptions,
    );
  }

  final CompactionStrategy _compactionStrategy;
  final LoggerFactory? _loggerFactory;
  late final ProviderSessionState<State> _sessionState;
  late final List<String> _stateKeys;

  @override
  List<String> get stateKeys => _stateKeys;

  static Future<Iterable<ChatMessage>> compact(
    CompactionStrategy compactionStrategy,
    Iterable<ChatMessage> messages, {
    Logger? logger,
    CancellationToken? cancellationToken,
  }) async {
    final messageIndex = CompactionMessageIndex.create(messages.toList());
    await compactionStrategy.compact(
      messageIndex,
      logger: logger,
      cancellationToken: cancellationToken,
    );
    return messageIndex.getIncludedMessages();
  }

  @override
  Future<AIContext> invokingCore(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final activity = CompactionTelemetry.activitySource.startActivity(
      CompactionTelemetry.activityNames.compactionProviderInvoke,
    );
    final loggerFactory = getLoggerFactory(context.agent);
    final logger = loggerFactory.createLogger('CompactionProvider');
    final session = context.session;
    final allMessages = context.aiContext.messages;

    if (session == null || allMessages == null) {
      logger.logCompactionProviderSkipped('no session or no messages');
      activity?.setTag(CompactionTelemetry.tags.compacted, false);
      return context.aiContext;
    }

    final chatClientSession =
        session.getService(ChatClientAgentSession) as ChatClientAgentSession?;
    if (chatClientSession != null &&
        chatClientSession.conversationId != null &&
        chatClientSession.conversationId!.trim().isNotEmpty) {
      logger.logCompactionProviderSkipped('session managed by remote service');
      activity?.setTag(CompactionTelemetry.tags.compacted, false);
      return context.aiContext;
    }

    final messageList = allMessages.toList();
    final state = _sessionState.getOrInitializeState(session);
    final CompactionMessageIndex messageIndex;

    if (state.messageGroups.isNotEmpty) {
      messageIndex = CompactionMessageIndex(List.of(state.messageGroups));
      _markGroupsAsChatHistory(messageIndex.groups);
      messageIndex.update(messageList);
    } else {
      messageIndex = CompactionMessageIndex.create(messageList);
    }

    final strategyName = _compactionStrategy.runtimeType.toString();
    final beforeMessages = messageIndex.includedMessageCount;
    logger.logCompactionProviderApplying(beforeMessages, strategyName);

    await _compactionStrategy.compact(
      messageIndex,
      logger: loggerFactory.createLogger(strategyName),
      cancellationToken: cancellationToken,
    );

    final afterMessages = messageIndex.includedMessageCount;
    if (afterMessages < beforeMessages) {
      logger.logCompactionProviderApplied(beforeMessages, afterMessages);
    }
    activity?.setTag(
      CompactionTelemetry.tags.compacted,
      afterMessages < beforeMessages,
    );

    state.messageGroups
      ..clear()
      ..addAll(messageIndex.groups);
    _sessionState.saveState(session, state);

    for (final message in messageIndex.groups.expand(
      (group) => group.messages,
    )) {
      final existingSourceType = message.getAgentRequestMessageSourceType();
      final wasInInput = messageList.any(
        (input) => input.contentEquals(message),
      );
      if (existingSourceType != AgentRequestMessageSourceType.chatHistory &&
          !wasInInput) {
        message.additionalProperties ??= <String, Object?>{};
        final stamped = message.withAgentRequestMessageSource(
          AgentRequestMessageSourceType.chatHistory,
          sourceId: runtimeType.toString(),
        );
        message.additionalProperties = stamped.additionalProperties;
      }
    }

    return AIContext()
      ..messages = messageIndex.getIncludedMessages()
      ..tools = context.aiContext.tools
      ..instructions = context.aiContext.instructions;
  }

  LoggerFactory getLoggerFactory(AIAgent agent) {
    final chatClient = agent.getService(ChatClient) as ChatClient?;
    return _loggerFactory ??
        chatClient?.getService<LoggerFactory>() ??
        NullLoggerFactory.instance;
  }

  void _markGroupsAsChatHistory(List<CompactionMessageGroup> groups) {
    for (final message in groups.expand((group) => group.messages)) {
      final stamped = message.withAgentRequestMessageSource(
        AgentRequestMessageSourceType.chatHistory,
        sourceId: runtimeType.toString(),
      );
      message.additionalProperties = stamped.additionalProperties;
    }
  }
}

/// Represents the persisted state of a [CompactionProvider] stored in the
/// session state bag.
class State {
  final List<CompactionMessageGroup> messageGroups = [];
}
