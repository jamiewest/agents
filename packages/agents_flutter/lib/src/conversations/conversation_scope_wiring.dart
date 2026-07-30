import 'package:agents/agents.dart'
    show
        ChatHistoryMemoryProvider,
        ChatHistoryMemoryProviderScope,
        ChatHistoryMemoryProviderState;
import 'package:extensions/extensions.dart';

import '../activity/terminal_activity.dart';
import '../activity/terminal_mirroring_shell_executor.dart';
import '../chat_history/flutter_chat_history_provider.dart';
import '../configured_agents/agent_scope.dart';
import '../configured_agents/models/saved_agent_config.dart';
import '../flutter_harness_agent_options.dart';
import '../memory/embedding_settings.dart';
import '../memory/memory_scorer.dart';
import '../memory/record_store_vector_store.dart';
import '../pushover/pushover_settings.dart';
import '../storage/record_store.dart';
import '../storage/record_store_agent_file_store.dart';
import '../temporal/temporal_tool.dart';
import '../user_profile/user_profile_context_provider.dart';
import '../user_profile/user_profile_settings.dart';
import '../web/headless_web_view_page_loader.dart';
import '../web/web_search_settings.dart';
import '../web/web_search_trace.dart';

/// The standard per-conversation harness wiring, extracted from the
/// reference app's `configureHarnessForScope` callback.
///
/// [apply] connects whatever relevant services are registered — Pushover
/// credentials, web search settings and tracing, the terminal registry, the
/// user profile, and (for durable conversations) the record-store-backed
/// chat history, file stores, and long-term memory. Services that are not
/// registered are simply skipped, so hosts opt into capabilities by
/// registering their settings objects, and the app callback shrinks to
/// app-specific wiring plus one [apply] call:
///
/// ```dart
/// configureHarnessForScope: (sp) => (agent, options, scope) {
///   // app-specific tool wiring here…
///   ConversationScopeWiring.apply(sp, agent, options, scope,
///       memoryApplicationId: 'my_app');
/// }
/// ```
abstract final class ConversationScopeWiring {
  /// Applies the standard wiring for [agent] running under [scope].
  ///
  /// [memoryApplicationId] namespaces long-term memory records.
  /// [staleToolResultNames] replay as expired markers from stored history
  /// (defaulting to the temporal tool, whose old readings must not be
  /// parroted from a past session). [memoryCollection] and
  /// [memoryDimensions] configure the vector store.
  static void apply(
    ServiceProvider services,
    SavedAgentConfig agent,
    FlutterHarnessAgentOptions options,
    AgentScope scope, {
    required String memoryApplicationId,
    Set<String> staleToolResultNames = const {currentTimeToolName},
    String memoryCollection = 'chat_memory',
    int memoryDimensions = 1536,
  }) {
    // Pushover: attach the client built from the stored credentials. The
    // factory strips it again for agents whose saved access settings do
    // not opt in, so which tools an agent gets is decided per agent in
    // the editor, not here.
    final pushover = services.getService<PushoverSettings>();
    if (pushover != null) {
      options.pushoverClient = pushover.client;
    }

    // Web search: attach the source for the configured search URL, plus
    // one source per categorized client so agents can steer a query to
    // the endpoint suited to its topic. The harness swaps the hosted
    // search marker for the local tools while a source is present, and
    // the agent's own web-search access toggle still gates both through
    // the factory.
    final webSearch = services.getService<WebSearchSettings>();
    options.webSearchSource = webSearch?.source;
    options.webSearchSourcesByCategory = webSearch?.sourcesByCategory;

    // Give `open_web_page` the same headless loader the harness would
    // create itself, sending the browsing user agent chosen in settings —
    // wrapped so each load lands in the trace log when tracing is
    // registered. Only while search is configured, so which agents get
    // the web tools is unchanged — `disableWebSearch` still gates them.
    if (options.webSearchSource != null) {
      final browsingUserAgent = webSearch?.browsingUserAgent;
      final loader = HeadlessWebViewPageLoader(userAgent: browsingUserAgent);
      final trace = services.getService<WebSearchTraceLog>();
      options.webPageLoader = trace == null
          ? loader
          : TracingWebPageLoader(loader, trace, userAgent: browsingUserAgent);
    }

    // Mirror the agent's shell commands into the conversation's in-chat
    // terminal. Decorating whatever executor the factory chose (local
    // shell today, ssh or container backends tomorrow) keeps the terminal
    // a pure observer of the real tool.
    final terminals = services.getService<TerminalActivity>();
    final shellExecutor = options.shellExecutor;
    if (terminals != null && shellExecutor != null) {
      options.shellExecutor = TerminalMirroringShellExecutor(
        shellExecutor,
        registry: terminals,
        conversationId: scope.conversationId,
      );
    }

    // Who the agent is talking to. Above the private-conversation return
    // below: a private chat is still with the same person, and the
    // provider persists nothing.
    final profile = services.getService<UserProfileSettings>();
    if (profile != null) {
      options.aiContextProviders = [
        ...?options.aiContextProviders,
        UserProfileContextProvider(profile),
      ];
    }

    // Private conversations keep the default in-memory capabilities;
    // durable ones read and write conversation-scoped persistence, so
    // resumed chats need no replay step.
    if (scope.isPrivate) return;
    final records = services.getRequiredService<RecordStore>();
    options.chatHistoryProvider = FlutterChatHistoryProvider(
      records,
      conversationId: scope.conversationId,
      sessionIdResolver: scope.sessionIdResolver,
      senderAgentId: agent.id,
      staleToolResultNames: staleToolResultNames,
    );

    // Agent-written files persist per conversation (or channel).
    final namespace = scope.channelId ?? scope.conversationId;
    options.fileAccessStore = RecordStoreAgentFileStore(
      records,
      namespace: namespace,
    );
    options.fileMemoryStore = RecordStoreAgentFileStore(
      records,
      namespace: '$namespace#memory',
    );

    // Long-term memory: whole-conversation recall through the vector
    // store, scoped so agents never see each other's memories.
    final scorer =
        services.getService<EmbeddingSettings>() as MemoryScorer? ??
        const KeywordOverlapScorer();
    options.aiContextProviders = [
      ...?options.aiContextProviders,
      ChatHistoryMemoryProvider(
        RecordStoreVectorStore(records, scorer: scorer),
        memoryCollection,
        memoryDimensions,
        (_) => ChatHistoryMemoryProviderState(
          ChatHistoryMemoryProviderScope(
            applicationId: memoryApplicationId,
            agentId: agent.id,
            // Channel conversations share channel-wide memory.
            sessionId: scope.channelId ?? scope.conversationId,
          ),
        ),
      ),
    ];
  }
}
