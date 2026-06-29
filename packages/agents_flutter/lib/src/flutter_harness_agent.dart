import 'dart:async';

import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';

import 'connectivity/connectivity_monitor.dart';
import 'device_info/device_info.dart';
import 'flutter_harness_agent_options.dart';
import 'flutter_harness_capabilities.dart';
import 'location/location_resolver.dart';
import 'package_info/app_info.dart';

/// A [HarnessAgent] preconfigured with Flutter device-capability context
/// providers and tools.
///
/// Wraps [ChatClient.asHarnessAgent] after merging the capabilities enabled by
/// [FlutterHarnessAgentOptions] into the underlying [HarnessAgentOptions], so a
/// caller gets a full harness — compaction, function invocation, per-call chat
/// history persistence — plus temporal, connectivity, app info, and device info
/// out of the box, with location, detailed network info, and the wake-lock tool
/// available opt-in.
///
/// This direct path runs no hosted services, so the device and app info caches
/// are populated in the background on construction. For DI/hosting use
/// `ServiceCollection.addFlutterHarness` (or `FlutterBuilder.useFlutterHarnessAgent`)
/// instead, where dedicated background services own population.
final class FlutterHarnessAgent extends DelegatingAIAgent {
  /// Creates a Flutter harness agent wrapping [chatClient].
  ///
  /// The [maxContextWindowTokens] and [maxOutputTokens] configure the harness
  /// compaction strategy, matching [ChatClient.asHarnessAgent]. The [options]
  /// select which Flutter capabilities are included and carry any standard
  /// [HarnessAgentOptions] configuration.
  FlutterHarnessAgent(
    ChatClient chatClient,
    int maxContextWindowTokens,
    int maxOutputTokens, {
    FlutterHarnessAgentOptions? options,
  }) : super(
         _buildAgent(
           chatClient,
           maxContextWindowTokens,
           maxOutputTokens,
           options,
         ),
       );

  static AIAgent _buildAgent(
    ChatClient chatClient,
    int maxContextWindowTokens,
    int maxOutputTokens,
    FlutterHarnessAgentOptions? options,
  ) {
    // Clone so merging Flutter capabilities never mutates the caller's options.
    final effectiveOptions = options?.clone() ?? FlutterHarnessAgentOptions();

    final deviceInfo = DeviceInfo();
    final appInfo = AppInfo();
    unawaited(populateFlutterDeviceCaches(deviceInfo, appInfo));

    final capabilities = buildFlutterHarnessCapabilities(
      effectiveOptions,
      clock: const Clock(),
      connectivityMonitor: ConnectivityMonitor(),
      deviceInfo: deviceInfo,
      appInfo: appInfo,
      locationResolver: LocationResolver(),
    );

    effectiveOptions.aiContextProviders = [
      ...?effectiveOptions.aiContextProviders,
      ...capabilities.providers,
    ];
    effectiveOptions.chatOptions ??= ChatOptions();
    effectiveOptions.chatOptions!.tools = [
      ...?effectiveOptions.chatOptions!.tools,
      ...capabilities.tools,
    ];

    return chatClient.asHarnessAgent(
      maxContextWindowTokens,
      maxOutputTokens,
      options: effectiveOptions,
    );
  }
}
