import 'package:extensions/ai.dart';
import 'package:http/http.dart' as http;

import '../activity/tool_activity.dart';
import '../logging/prompt_logging_chat_client.dart';
import '../logging/prompt_log.dart';
import '../telemetry/agent_run_scope.dart';
import '../telemetry/usage_store.dart';
import 'agent_scope.dart';
import 'configured_chat_client_factory.dart';
import 'models/model_config.dart';
import 'models/model_source_config.dart';
import 'models/provider_type.dart';
import 'usage_tracking_chat_client.dart';

/// A [ConfiguredChatClientFactory] that captures every prompt it produces.
///
/// Wraps each cloud provider's client in a [PromptLoggingChatClient] so the request
/// (system instructions, declared tools, and message history) lands in [log].
/// Local llama clients already capture their exact wire-format prompt through
/// the host's shared prompt inspector, so they are returned unwrapped to
/// avoid logging the same turn twice.
///
/// When a [usageSink] is supplied, every client — local llama included — is
/// additionally wrapped in a [UsageTrackingChatClient] so each model call's
/// token usage lands in the durable ledger and on the response messages.
/// Private conversations report to a [DiscardingUsageRecordSink] instead:
/// per-message usage still reaches the UI, but nothing is persisted.
class LoggingConfiguredChatClientFactory extends ConfiguredChatClientFactory {
  /// Creates a factory that records prompts into [log].
  LoggingConfiguredChatClientFactory({
    required this.log,
    this.usageSink,
    this.toolActivity,
    super.isWeb,
    super.customClientResolver,
  });

  /// The unified prompt log every produced client writes to.
  final PromptLog log;

  /// The ledger receiving one usage record per model call, when tracking is
  /// enabled.
  final UsageRecordSink? usageSink;

  /// Receives the running tools' names during a turn, when supplied, so the
  /// chat UI can show live tool activity.
  final ToolActivity? toolActivity;

  @override
  ChatClient createChatClient({
    required ModelSourceConfig source,
    required ModelConfig model,
    String? apiKey,
    http.Client? httpClient,
    AgentScope? scope,
  }) {
    final inner = super.createChatClient(
      source: source,
      model: model,
      apiKey: apiKey,
      httpClient: httpClient,
      scope: scope,
    );
    final logged = source.providerType == ProviderType.localLlama
        ? inner
        : PromptLoggingChatClient(
            inner,
            log: log,
            title: '${source.providerType.name} · ${model.modelId}',
          );
    final sink = usageSink;
    final tracked = sink == null
        ? logged
        : UsageTrackingChatClient(
            logged,
            sink: _sinkFor(sink, scope),
            modelId: model.modelId,
            sourceId: source.id,
            provider: source.providerType.name,
            scope: scope,
          );
    final activity = toolActivity;
    final conversationId = scope?.conversationId;
    // Scope-less clients (e.g. hosting internals or the title summarizer)
    // have no conversation channel to publish into, so they go untracked
    // rather than surfacing activity under an unrelated open chat.
    if (activity == null || conversationId == null) return tracked;
    return ToolActivityTrackingChatClient(
      tracked,
      registry: activity,
      conversationId: conversationId,
    );
  }

  /// Chooses the usage sink for [scope].
  ///
  /// Private conversations discard, exactly as before. Otherwise, when the
  /// caller supplied an [AgentRunScope] and the sink is a [UsageStore],
  /// records are attributed to the scope's agent and to the run in flight.
  /// Any other combination falls through to the plain sink, so a test double
  /// or a scope-less internal caller still records usage — just without
  /// agent attribution.
  static UsageRecordSink _sinkFor(UsageRecordSink sink, AgentScope? scope) {
    if (scope?.isPrivate ?? false) return const DiscardingUsageRecordSink();
    if (scope is AgentRunScope && sink is UsageStore) {
      return sink.attributedTo(scope);
    }
    return sink;
  }
}
