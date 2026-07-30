import 'package:extensions/ai.dart' as ai;
import 'package:extensions_flutter/extensions_flutter.dart';

import '../activity/app_activity_monitor.dart';
import '../chat_history/chat_transcript_store.dart';
import '../storage/record_store.dart';
import 'channel_store.dart';
import 'chat_title_summarizer.dart';
import 'conversation_service.dart';
import 'conversation_store.dart';

/// Registers the conversation domain into a [ServiceCollection].
extension ConversationsServiceCollectionExtensions on ServiceCollection {
  /// Registers the conversation metadata stores and services.
  ///
  /// Adds [ConversationStore], [ConversationSessionStore], [ChannelStore],
  /// [ChatTranscriptStore], and [ConversationService], each backed by the
  /// registered [RecordStore]. Everything is `tryAddSingleton`, so a store
  /// registered earlier (a test fake, or a host-specific implementation)
  /// wins.
  ServiceCollection addConversations() {
    tryAddSingleton<ConversationStore>(
      (sp) => ConversationStore(sp.getRequiredService<RecordStore>()),
    );
    tryAddSingleton<ConversationSessionStore>(
      (sp) => ConversationSessionStore(sp.getRequiredService<RecordStore>()),
    );
    tryAddSingleton<ChannelStore>(
      (sp) => ChannelStore(sp.getRequiredService<RecordStore>()),
    );
    tryAddSingleton<ChatTranscriptStore>(
      (sp) => ChatTranscriptStore(sp.getRequiredService<RecordStore>()),
    );
    tryAddSingleton<ConversationService>(
      (sp) => ConversationService(sp.getRequiredService<ConversationStore>()),
    );
    return this;
  }

  /// Registers the [ChatTitleSummarizer] under the host lifecycle.
  ///
  /// The summarizer names placeholder-titled conversations while the app is
  /// idle, using whatever client [residentTitleClient] returns at that
  /// moment — typically the already-resident local model, and null when
  /// nothing suitable is loaded (the summarizer then skips the pass rather
  /// than loading a model itself).
  ///
  /// Requires [addConversations] (or equivalent registrations) plus a
  /// registered [AppActivityMonitor].
  ServiceCollection addChatTitleSummarizer({
    required ai.ChatClient? Function(ServiceProvider services)
    residentTitleClient,
  }) {
    tryAddSingleton<AppActivityMonitor>((_) => AppActivityMonitor());
    addHostedService<ChatTitleSummarizer>(
      (sp) => ChatTitleSummarizer(
        conversations: sp.getRequiredService<ConversationStore>(),
        transcripts: sp.getRequiredService<ChatTranscriptStore>(),
        activity: sp.getRequiredService<AppActivityMonitor>(),
        residentTitleClient: () => residentTitleClient(sp),
        loggerFactory: sp.getRequiredService<LoggerFactory>(),
      ),
    );
    return this;
  }
}
