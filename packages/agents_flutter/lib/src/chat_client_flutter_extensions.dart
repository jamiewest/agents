import 'dart:async';

import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';

import 'connectivity/connectivity_monitor.dart';
import 'device_info/device_info.dart';
import 'flutter_harness_agent.dart';
import 'flutter_harness_agent_options.dart';
import 'flutter_harness_capabilities.dart';
import 'location/location_resolver.dart';
import 'network/network_context_provider.dart';
import 'package_info/app_info.dart';

/// Creates a [FlutterHarnessAgent] from a [ChatClient].
extension ChatClientFlutterHarnessExtensions on ChatClient {
  /// Creates a [FlutterHarnessAgent] that wraps this [ChatClient] with the
  /// harness pipeline plus the Flutter device-capability providers and tools.
  ///
  /// The [maxContextWindowTokens] is the model's context-window size and
  /// [maxOutputTokens] the per-response output limit; both configure the
  /// compaction strategy, matching [ChatClient.asHarnessAgent].
  ///
  /// The [options] select which Flutter capabilities are included (safe-core on
  /// by default; location, network info, and wake lock opt-in) and carry any
  /// standard [HarnessAgentOptions] configuration.
  FlutterHarnessAgent asFlutterHarnessAgent(
    int maxContextWindowTokens,
    int maxOutputTokens, {
    FlutterHarnessAgentOptions? options,
  }) {
    return FlutterHarnessAgent(
      this,
      maxContextWindowTokens,
      maxOutputTokens,
      options: options,
    );
  }
}

/// Appends the Flutter device-capability providers and tools to a
/// [ChatClientAgentOptions].
extension FlutterHarnessChatClientAgentOptionsExtensions
    on ChatClientAgentOptions {
  /// Appends the enabled Flutter context providers and tools, preserving any
  /// existing providers and tools.
  ///
  /// Safe-core capabilities (temporal, connectivity, app info, device info) are
  /// on by default; location, detailed network info, and the wake-lock tool are
  /// opt-in. Connectivity is appended last.
  ///
  /// Runtime services are created when not supplied; injected instances are
  /// used as-is for testing. Because no hosted services run on this path, the
  /// device and app info caches are populated in the background unless both are
  /// supplied by the caller.
  ChatClientAgentOptions addFlutterHarnessContext({
    bool enableTemporal = true,
    bool enableConnectivity = true,
    bool enableAppInfo = true,
    bool enableDeviceInfo = true,
    bool enableLocation = false,
    bool enableNetworkInfo = false,
    bool enableWakeLock = false,
    String? timeZoneId,
    Clock? clock,
    ConnectivityMonitor? connectivityMonitor,
    DeviceInfo? deviceInfo,
    AppInfo? appInfo,
    LocationResolver? locationResolver,
    NetworkInfoSource? networkInfoSource,
  }) {
    final capabilityOptions = FlutterHarnessAgentOptions(
      enableTemporal: enableTemporal,
      enableConnectivity: enableConnectivity,
      enableAppInfo: enableAppInfo,
      enableDeviceInfo: enableDeviceInfo,
      enableLocation: enableLocation,
      enableNetworkInfo: enableNetworkInfo,
      enableWakeLock: enableWakeLock,
      timeZoneId: timeZoneId,
    );

    final effectiveDeviceInfo = deviceInfo ?? DeviceInfo();
    final effectiveAppInfo = appInfo ?? AppInfo();
    if (deviceInfo == null || appInfo == null) {
      unawaited(
        populateFlutterDeviceCaches(effectiveDeviceInfo, effectiveAppInfo),
      );
    }

    // Live platform resources are created only when their capability is
    // enabled; an internally created monitor lives for the process, so pass
    // one in when disposal matters.
    final capabilities = buildFlutterHarnessCapabilities(
      capabilityOptions,
      clock: clock ?? const Clock(),
      connectivityMonitor:
          connectivityMonitor ??
          (enableConnectivity ? ConnectivityMonitor() : null),
      deviceInfo: effectiveDeviceInfo,
      appInfo: effectiveAppInfo,
      locationResolver:
          locationResolver ?? (enableLocation ? LocationResolver() : null),
      networkInfoSource: networkInfoSource,
    );

    aiContextProviders = [...?aiContextProviders, ...capabilities.providers];
    if (capabilities.tools.isNotEmpty) {
      chatOptions ??= ChatOptions();
      chatOptions!.tools = [...?chatOptions!.tools, ...capabilities.tools];
    }

    return this;
  }
}
