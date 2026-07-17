import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';

import 'connectivity/connectivity_context_provider.dart';
import 'connectivity/connectivity_monitor.dart';
import 'connectivity/connectivity_tool.dart';
import 'device_info/device_context_provider.dart';
import 'device_info/device_info.dart';
import 'device_info/device_info_gatherer.dart';
import 'device_info/device_info_tool.dart';
import 'flutter_harness_agent_options.dart';
import 'location/location_context_provider.dart';
import 'location/location_resolver.dart';
import 'location/location_tool.dart';
import 'network/network_context_provider.dart';
import 'network/network_tool.dart';
import 'package_info/app_info.dart';
import 'package_info/app_info_loader.dart';
import 'package_info/package_info_tool.dart';
import 'temporal/temporal_context_provider.dart';
import 'temporal/temporal_tool.dart';
import 'wake_lock/wake_lock_tool.dart';

/// The Flutter context providers and tools enabled by a set of options.
typedef FlutterHarnessCapabilities = ({
  List<AIContextProvider> providers,
  List<AITool> tools,
});

/// Builds the Flutter context providers and tools enabled by [options].
///
/// This is the single source of truth for capability order across every entry
/// point ([FlutterHarnessAgent], `ChatClientAgentOptions.addFlutterHarnessContext`,
/// and `ServiceCollection.addFlutterHarness`). The connectivity capability is
/// always appended last so its volatile offline marker sits at the end of the
/// cached prompt prefix.
///
/// The runtime services are supplied by the caller so the same provider/tool
/// set can be backed by DI singletons (hosting) or freshly created instances
/// (direct construction). When [networkInfoSource] is `null` and network info
/// is enabled, the plugin-backed source is used.
///
/// [connectivityMonitor] and [locationResolver] hold live platform resources,
/// so callers create them only for enabled capabilities; they are required
/// exactly when the corresponding capability is enabled.
FlutterHarnessCapabilities buildFlutterHarnessCapabilities(
  FlutterHarnessAgentOptions options, {
  required Clock clock,
  required DeviceInfo deviceInfo,
  required AppInfo appInfo,
  ConnectivityMonitor? connectivityMonitor,
  LocationResolver? locationResolver,
  NetworkInfoSource? networkInfoSource,
}) {
  if (options.enableConnectivity && connectivityMonitor == null) {
    throw ArgumentError.notNull('connectivityMonitor');
  }
  if (options.enableLocation && locationResolver == null) {
    throw ArgumentError.notNull('locationResolver');
  }

  final providers = <AIContextProvider>[];
  final tools = <AITool>[];

  if (options.enableTemporal) {
    providers.add(
      TemporalContextProvider(clock: clock, timeZoneId: options.timeZoneId),
    );
    tools.add(
      createCurrentTimeTool(clock: clock, timeZoneId: options.timeZoneId),
    );
  }

  if (options.enableDeviceInfo) {
    providers.add(DeviceContextProvider(deviceInfo));
    tools.add(createGetDeviceInfoTool(deviceInfo));
  }

  if (options.enableAppInfo) {
    tools.add(createGetAppInfoTool(appInfo));
  }

  if (options.enableLocation) {
    providers.add(LocationContextProvider(locationResolver!));
    tools.add(createCurrentLocationTool());
    tools.add(createGeocodeAddressTool());
  }

  // Network info is deliberately tool-only: NetworkContextProvider polls six
  // platform channels per turn and injects volatile values (SSID, IPs) into
  // instructions, violating both KV-cache rules. The tool covers on-demand
  // lookups; compose the provider manually if ambient context is essential.
  if (options.enableNetworkInfo) {
    tools.add(createCurrentNetworkInfoTool(source: networkInfoSource));
  }

  if (options.enableWakeLock) {
    tools.add(createWakeLockTool());
  }

  // Connectivity is always last: see [buildFlutterHarnessCapabilities].
  if (options.enableConnectivity) {
    providers.add(ConnectivityContextProvider(connectivityMonitor!));
    tools.add(createConnectivityTool());
  }

  return (providers: providers, tools: tools);
}

/// Populates the device and app info caches from the platform in the
/// background, swallowing any plugin failures.
///
/// Used by the hostless paths where no [DeviceInfoHostedService] or
/// [PackageInfoHostedService] runs. The caches are read-after-write safe: the
/// `get_device_info` and `get_app_info` tools report a not-available message
/// during the brief window before population completes.
Future<void> populateFlutterDeviceCaches(
  DeviceInfo deviceInfo,
  AppInfo appInfo,
) async {
  await Future.wait([populateDeviceInfo(deviceInfo), populateAppInfo(appInfo)]);
}
