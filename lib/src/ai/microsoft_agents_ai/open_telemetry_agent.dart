import 'package:extensions/system.dart';
import 'package:extensions/ai.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_response_update.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_run_options.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/agent_session.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent_metadata.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/delegating_ai_agent.dart';
import '../microsoft_agents_ai_purview/models/common/activity.dart';
import 'open_telemetry_consts.dart';
import '../../activity_stubs.dart';
import '../../abstractions/microsoft_agents_ai_abstractions/ai_agent.dart';

/// Provides a delegating [AIAgent] implementation that implements the
/// OpenTelemetry Semantic Conventions for Generative AI systems.
///
/// Remarks: This class provides an implementation of the Semantic Conventions
/// for Generative AI systems v1.37, defined at . The specification is still
/// experimental and subject to change; as such, the telemetry output by this
/// client is also subject to change.
class OpenTelemetryAgent extends DelegatingAIAgent implements Disposable {
  /// Initializes a new instance of the [OpenTelemetryAgent] class.
  ///
  /// Remarks: The constructor automatically extracts provider metadata from the
  /// inner agent and configures telemetry collection according to OpenTelemetry
  /// semantic conventions for AI systems.
  ///
  /// [innerAgent] The underlying [AIAgent] to be augmented with telemetry
  /// capabilities.
  ///
  /// [sourceName] An optional source name that will be used to identify
  /// telemetry data from this agent. If not provided, a default source name
  /// will be used for telemetry identification.
  OpenTelemetryAgent(AIAgent innerAgent, {String? sourceName = null, }) {
    this._providerName = innerAgent.getService<AIAgentMetadata>()?.providerName;
    this._otelClient = openTelemetryChatClient(
            forwardingChatClient(this),
            sourceName: (sourceName == null || sourceName.isEmpty) ? OpenTelemetryConsts.defaultSourceName : sourceName!);
  }

  /// The [OpenTelemetryChatClient] providing the bulk of the telemetry.
  late final OpenTelemetryChatClient _otelClient;

  /// The provider name extracted from [AIAgentMetadata].
  late final String? _providerName;

  /// Gets or sets a value indicating whether potentially sensitive information
  /// should be included in telemetry.
  ///
  /// Remarks: By default, telemetry includes metadata, such as token counts,
  /// but not raw inputs and outputs, such as message content, function call
  /// arguments, and function call results. The default value can be overridden
  /// by setting the `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`
  /// environment variable to "true". Explicitly setting this property will
  /// override the environment variable. Security consideration: When sensitive
  /// data capture is enabled, the full text of chat messages — including user
  /// inputs, LLM responses, function call arguments, and function results — is
  /// emitted as telemetry. This data may contain PII or other sensitive
  /// information. Ensure that your telemetry pipeline is configured with
  /// appropriate access controls and data retention policies.
  bool enableSensitiveData;

  @override
  void dispose() {
    this._otelClient.dispose();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    var co = forwardedOptions(options, session, Activity.current);
    var response = await this._otelClient.getResponseAsync(
      messages,
      co,
      cancellationToken,
    ) ;
    return response.rawRepresentation as AgentResponse ?? agentResponse(response);
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages,
    {AgentSession? session, AgentRunOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    var co = forwardedOptions(options, session, Activity.current);
    for (final update in this._otelClient.getStreamingResponseAsync(messages, co, cancellationToken)) {
      yield update.rawRepresentation as AgentResponseUpdate ?? AgentResponseUpdate(role: update);
    }
  }

  /// Augments the current activity created by the [OpenTelemetryChatClient]
  /// with agent-specific information.
  ///
  /// [previousActivity] The [Activity] that was current prior to the
  /// [OpenTelemetryChatClient]'s invocation.
  void updateCurrentActivity(Activity? previousActivity) {
    if (Activity.current is not { } activity ||
            identical(activity, previousActivity)) {
      return;
    }
    // Override information set by OpenTelemetryChatClient to make it specific to invoke_agent.

        activity.displayName = (this.name == null || this.name.trim().isEmpty)
            ? '${OpenTelemetryConsts.genAI.invokeAgent} ${this.id}'
            : '${OpenTelemetryConsts.genAI.invokeAgent} ${this.name}(${this.id})';
    activity.setTag(
      OpenTelemetryConsts.genAI.operation.name,
      OpenTelemetryConsts.genAI.invokeAgent,
    );
    if (!(this._providerName == null || this._providerName.trim().isEmpty)) {
      _ = activity.setTag(OpenTelemetryConsts.genAI.provider.name, this._providerName);
    }
    // Further augment the activity with agent-specific tags.

        _ = activity.setTag(OpenTelemetryConsts.genAI.agent.id, this.id);
    if (this.name is { } name && !(name == null || name.trim().isEmpty)) {
      _ = activity.setTag(OpenTelemetryConsts.genAI.agent.name, this.name);
    }
    if (this.description is { } description && !(description == null || description.trim().isEmpty)) {
      _ = activity.setTag(OpenTelemetryConsts.genAI.agent.description, description);
    }
  }
}
/// State passed from this instance into the inner agent, circumventing the
/// intermediate [OpenTelemetryChatClient].
class ForwardedOptions extends ChatOptions {
  ForwardedOptions(
    AgentRunOptions? options,
    AgentSession? session,
    Activity? currentActivity,
  ) :
      options = options,
      session = session,
      currentActivity = currentActivity {
  }

  final AgentRunOptions? options;

  final AgentSession? session;

  final Activity? currentActivity;

}
/// The stub [ChatClient] used to delegate from the [OpenTelemetryChatClient]
/// into the inner [AIAgent].
///
/// [parentAgent]
class ForwardingChatClient extends ChatClient {
  /// The stub [ChatClient] used to delegate from the [OpenTelemetryChatClient]
  /// into the inner [AIAgent].
  ///
  /// [parentAgent]
  const ForwardingChatClient(OpenTelemetryAgent parentAgent);

  Future<ChatResponse> getResponse(
    Iterable<ChatMessage> messages,
    {ChatOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    var fo = options as ForwardedOptions;
    // Update the current activity to reflect the agent invocation.
            parentAgent.updateCurrentActivity(fo?.currentActivity);
    var response = await parentAgent.innerAgent.runAsync(
      messages,
      fo?.session,
      fo?.options,
      cancellationToken,
    ) ;
    return response.asChatResponse();
  }

  Stream<ChatResponseUpdate> getStreamingResponse(
    Iterable<ChatMessage> messages,
    {ChatOptions? options, CancellationToken? cancellationToken, },
  ) async  {
    var fo = options as ForwardedOptions;
    // Update the current activity to reflect the agent invocation.
            parentAgent.updateCurrentActivity(fo?.currentActivity);
    for (final update in parentAgent.innerAgent.runStreamingAsync(messages, fo?.session, fo?.options, cancellationToken)) {
      yield update.asChatResponseUpdate();
    }
  }

  Object? getService(Type serviceType, {Object? serviceKey, }) {
    return // Delegate any inquiries made by the OpenTelemetryChatClient back to the parent agent.
            parentAgent.getService(serviceType, serviceKey);
  }

  void dispose() {

  }
}
