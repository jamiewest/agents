import 'package:extensions/ai.dart' hide OpenTelemetryConsts;
import 'package:extensions/system.dart';

import '../abstractions/agent_response.dart';
import '../abstractions/agent_response_extensions.dart';
import '../abstractions/agent_response_update.dart';
import '../abstractions/agent_run_options.dart';
import '../abstractions/agent_session.dart';
import '../abstractions/ai_agent.dart';
import '../abstractions/ai_agent_metadata.dart';
import '../abstractions/delegating_ai_agent.dart';
import '../activity_stubs.dart';
import 'open_telemetry_consts.dart';

/// Provides a delegating [AIAgent] implementation that instruments agent
/// operations via [OpenTelemetryChatClient].
class OpenTelemetryAgent extends DelegatingAIAgent implements Disposable {
  OpenTelemetryAgent(AIAgent innerAgent, {String? sourceName})
    : super(innerAgent) {
    final metadata = innerAgent.getService(AIAgentMetadata) as AIAgentMetadata?;
    _providerName = metadata?.providerName;
    _otelClient = OpenTelemetryChatClient(
      ForwardingChatClient(this),
      system: (sourceName == null || sourceName.isEmpty)
          ? OpenTelemetryConsts.defaultSourceName
          : sourceName,
    );
  }

  late final OpenTelemetryChatClient _otelClient;
  late final String? _providerName;

  /// Gets or sets a value indicating whether potentially sensitive
  /// information should be included in telemetry.
  bool enableSensitiveData = false;

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final response = await _otelClient.getResponse(
      messages: messages,
      options: ForwardedOptions(options, session, Activity.current),
      cancellationToken: cancellationToken,
    );
    final raw = response.rawRepresentation;
    return raw is AgentResponse ? raw : AgentResponse(response: response);
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final updates = _otelClient.getStreamingResponse(
      messages: messages,
      options: ForwardedOptions(options, session, Activity.current),
      cancellationToken: cancellationToken,
    );
    await for (final update in updates) {
      final raw = update.rawRepresentation;
      yield raw is AgentResponseUpdate
          ? raw
          : AgentResponseUpdate(chatResponseUpdate: update);
    }
  }

  /// Augments the current activity with agent-specific information.
  void updateCurrentActivity(Activity? previousActivity) {
    final activity = Activity.current;
    if (activity == null || identical(activity, previousActivity)) {
      return;
    }

    activity.displayName = (name?.trim().isEmpty ?? true)
        ? '${OpenTelemetryConsts.genAI.invokeAgent} $id'
        : '${OpenTelemetryConsts.genAI.invokeAgent} $name($id)';
    activity.setTag(
      OpenTelemetryConsts.genAI.operation.name,
      OpenTelemetryConsts.genAI.invokeAgent,
    );
    if (_providerName?.trim().isNotEmpty == true) {
      activity.setTag(OpenTelemetryConsts.genAI.provider.name, _providerName);
    }
    activity.setTag(OpenTelemetryConsts.genAI.agent.id, id);
    if (name?.trim().isNotEmpty == true) {
      activity.setTag(OpenTelemetryConsts.genAI.agent.name, name);
    }
    if (description?.trim().isNotEmpty == true) {
      activity.setTag(OpenTelemetryConsts.genAI.agent.description, description);
    }
  }

  @override
  void dispose() {
    _otelClient.dispose();
  }
}

/// State passed from this instance into the inner agent, circumventing the
/// intermediate [OpenTelemetryChatClient].
class ForwardedOptions extends ChatOptions {
  ForwardedOptions(this.options, this.session, this.currentActivity);

  final AgentRunOptions? options;
  final AgentSession? session;
  final Activity? currentActivity;
}

/// The stub [ChatClient] used to delegate from [OpenTelemetryChatClient] into
/// the inner [AIAgent].
class ForwardingChatClient extends ChatClient {
  ForwardingChatClient(this.parentAgent);

  final OpenTelemetryAgent parentAgent;

  @override
  Future<ChatResponse> getResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async {
    final forwarded = options as ForwardedOptions;
    parentAgent.updateCurrentActivity(forwarded.currentActivity);
    final response = await parentAgent.innerAgent.runCore(
      messages,
      session: forwarded.session,
      options: forwarded.options,
      cancellationToken: cancellationToken,
    );
    return response.asChatResponse();
  }

  @override
  Stream<ChatResponseUpdate> getStreamingResponse({
    required Iterable<ChatMessage> messages,
    ChatOptions? options,
    CancellationToken? cancellationToken,
  }) async* {
    final forwarded = options as ForwardedOptions;
    parentAgent.updateCurrentActivity(forwarded.currentActivity);
    await for (final update in parentAgent.innerAgent.runCoreStreaming(
      messages,
      session: forwarded.session,
      options: forwarded.options,
      cancellationToken: cancellationToken,
    )) {
      yield update.asChatResponseUpdate();
    }
  }

  @override
  T? getService<T>({Object? key}) {
    final value = parentAgent.getService(T, serviceKey: key);
    return value is T ? value : null;
  }

  @override
  void dispose() {}
}
