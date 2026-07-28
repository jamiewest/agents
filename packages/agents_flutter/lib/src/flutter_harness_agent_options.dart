import 'package:agents/agents.dart';

import 'pushover/pushover_api.dart';
import 'pushover/pushover_tool.dart';

/// Configuration for a [FlutterHarnessAgent].
///
/// Extends [HarnessAgentOptions] with toggles for the Flutter device-capability
/// providers and tools. All [HarnessAgentOptions] behavior is preserved: the
/// enabled Flutter capabilities are appended to [aiContextProviders] and
/// [chatOptions] tools before the agent is built, leaving any caller-supplied
/// providers, tools, and instructions intact.
///
/// The safe-core capabilities (temporal, connectivity, app info, device info)
/// are passive and read-only, so they default on. Location, detailed local
/// network info, and the wake-lock tool touch more sensitive surfaces, so they
/// are opt-in.
class FlutterHarnessAgentOptions extends HarnessAgentOptions {
  /// Creates options for a [FlutterHarnessAgent].
  FlutterHarnessAgentOptions({
    this.enableTemporal = true,
    this.enableConnectivity = true,
    this.enableAppInfo = true,
    this.enableDeviceInfo = true,
    this.enableLocation = false,
    this.enableNetworkInfo = false,
    this.enableWakeLock = false,
    this.timeZoneId,
    this.pushoverClient,
    this.pushoverToolOptions,
  });

  /// When `true`, adds the temporal context provider and `get_current_time`
  /// tool. Defaults to `true`.
  bool enableTemporal;

  /// When `true`, adds the connectivity context provider and `get_connectivity`
  /// tool. Defaults to `true`. Registered last so its volatile offline marker
  /// sits at the end of the cached prompt prefix.
  bool enableConnectivity;

  /// When `true`, adds the `get_app_info` tool backed by cached app metadata.
  /// Defaults to `true`.
  bool enableAppInfo;

  /// When `true`, adds the device context provider and `get_device_info` tool
  /// backed by cached device info. Defaults to `true`.
  bool enableDeviceInfo;

  /// When `true`, adds the location context provider plus the
  /// `get_current_location` and `geocode_address` tools. Defaults to `false`.
  bool enableLocation;

  /// When `true`, adds the `get_current_network_info` tool. Defaults to
  /// `false`. Tool-only: the network context provider is never registered by
  /// the harness because its per-turn platform reads and volatile values
  /// would invalidate the cached prompt prefix.
  bool enableNetworkInfo;

  /// When `true`, adds the `set_wake_lock` tool. Defaults to `false`.
  bool enableWakeLock;

  /// An explicit IANA time-zone override for temporal context, or `null` to
  /// detect the device zone.
  String? timeZoneId;

  /// When set, adds the Pushover notification tools bound to this client.
  ///
  /// Unlike the passive device capabilities, these tools send a real
  /// notification to a real person, so there is no enable flag: the tools
  /// exist exactly when the host has attached a configured client. The
  /// recipient is fixed by the client, never chosen by the model.
  ///
  /// Saved-agent access settings gate this per agent: `ConfiguredAgentFactory`
  /// removes the client for agents whose `AgentAccessConfig.enablePushover`
  /// is `false`.
  PushoverClient? pushoverClient;

  /// Configuration for the tools added by [pushoverClient], or `null` for
  /// the defaults (send + quota tools, no emergency priority).
  PushoverToolOptions? pushoverToolOptions;

  /// Returns a shallow copy of these options.
  ///
  /// [chatOptions] is cloned and [aiContextProviders] is copied into a new list,
  /// so merging Flutter capabilities into the copy never mutates the original.
  /// Other reference-typed fields (stores, sources, agents) are shared.
  FlutterHarnessAgentOptions clone() {
    return FlutterHarnessAgentOptions(
        enableTemporal: enableTemporal,
        enableConnectivity: enableConnectivity,
        enableAppInfo: enableAppInfo,
        enableDeviceInfo: enableDeviceInfo,
        enableLocation: enableLocation,
        enableNetworkInfo: enableNetworkInfo,
        enableWakeLock: enableWakeLock,
        timeZoneId: timeZoneId,
        pushoverClient: pushoverClient,
        pushoverToolOptions: pushoverToolOptions,
      )
      ..id = id
      ..name = name
      ..description = description
      ..chatOptions = chatOptions?.clone()
      ..harnessInstructions = harnessInstructions
      ..chatHistoryProvider = chatHistoryProvider
      ..aiContextProviders = aiContextProviders == null
          ? null
          : List.of(aiContextProviders!)
      ..maximumIterationsPerRequest = maximumIterationsPerRequest
      ..disableToolApproval = disableToolApproval
      ..disableFileMemory = disableFileMemory
      ..fileMemoryStore = fileMemoryStore
      ..disableFileAccess = disableFileAccess
      ..fileAccessStore = fileAccessStore
      ..disableWebSearch = disableWebSearch
      ..disableTodoProvider = disableTodoProvider
      ..disableAgentModeProvider = disableAgentModeProvider
      ..agentModeProviderOptions = agentModeProviderOptions
      ..disableAgentSkillsProvider = disableAgentSkillsProvider
      ..agentSkillsSource = agentSkillsSource
      ..disableOpenTelemetry = disableOpenTelemetry
      ..openTelemetrySourceName = openTelemetrySourceName
      ..backgroundAgents = backgroundAgents
      ..backgroundAgentsProviderOptions = backgroundAgentsProviderOptions
      ..summarizationChatClient = summarizationChatClient
      ..enableSummarizationCompaction = enableSummarizationCompaction
      ..shellExecutor = shellExecutor
      ..shellEnvironmentProviderOptions = shellEnvironmentProviderOptions;
  }
}
