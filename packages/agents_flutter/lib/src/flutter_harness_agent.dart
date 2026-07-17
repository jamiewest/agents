import 'dart:async';

import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:flutter/foundation.dart';

import 'connectivity/connectivity_monitor.dart';
import 'device_info/device_info.dart';
import 'device_info/device_info_gatherer.dart';
import 'flutter_harness_agent_options.dart';
import 'flutter_harness_capabilities.dart';
import 'flutter_harness_platform_defaults.dart';
import 'location/location_resolver.dart';
import 'package_info/app_info.dart';
import 'package_info/app_info_loader.dart';

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
/// are populated in the background on construction, and the agent owns the
/// platform resources it creates — call [dispose] when done with it. For
/// DI/hosting use `ServiceCollection.addFlutterHarness` (or
/// `FlutterBuilder.useFlutterHarnessAgent`) instead, where dedicated background
/// services own population and the service provider owns disposal.
final class FlutterHarnessAgent extends DelegatingAIAgent
    implements Disposable {
  /// Creates a Flutter harness agent wrapping [chatClient].
  ///
  /// The [maxContextWindowTokens] and [maxOutputTokens] configure the harness
  /// compaction strategy, matching [ChatClient.asHarnessAgent]. The [options]
  /// select which Flutter capabilities are included and carry any standard
  /// [HarnessAgentOptions] configuration.
  factory FlutterHarnessAgent(
    ChatClient chatClient,
    int maxContextWindowTokens,
    int maxOutputTokens, {
    FlutterHarnessAgentOptions? options,
  }) {
    // Clone so merging Flutter capabilities never mutates the caller's options.
    final effectiveOptions = options?.clone() ?? FlutterHarnessAgentOptions();
    applyFlutterHarnessPlatformDefaults(effectiveOptions, isWeb: kIsWeb);

    final deviceInfo = DeviceInfo();
    final appInfo = AppInfo();
    if (effectiveOptions.enableDeviceInfo) {
      unawaited(populateDeviceInfo(deviceInfo));
    }
    if (effectiveOptions.enableAppInfo) {
      unawaited(populateAppInfo(appInfo));
    }

    // Live platform resources are created only for enabled capabilities and
    // owned by the agent; dispose releases them.
    final connectivityMonitor = effectiveOptions.enableConnectivity
        ? ConnectivityMonitor()
        : null;
    final locationResolver = effectiveOptions.enableLocation
        ? LocationResolver()
        : null;

    final capabilities = buildFlutterHarnessCapabilities(
      effectiveOptions,
      clock: const Clock(),
      connectivityMonitor: connectivityMonitor,
      deviceInfo: deviceInfo,
      appInfo: appInfo,
      locationResolver: locationResolver,
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

    return FlutterHarnessAgent._(
      chatClient.asHarnessAgent(
        maxContextWindowTokens,
        maxOutputTokens,
        options: effectiveOptions,
      ),
      connectivityMonitor,
      locationResolver,
    );
  }

  FlutterHarnessAgent._(
    super.innerAgent,
    this._connectivityMonitor,
    this._locationResolver,
  );

  final ConnectivityMonitor? _connectivityMonitor;
  final LocationResolver? _locationResolver;

  /// Releases the platform resources owned by this agent, such as the
  /// connectivity subscription.
  @override
  void dispose() {
    _connectivityMonitor?.dispose();
    _locationResolver?.dispose();
  }
}
