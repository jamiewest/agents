import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/hosting.dart';
import 'package:extensions/logging.dart';

import 'connectivity/connectivity_monitor.dart';
import 'device_info/device_info.dart';
import 'device_info/device_info_hosted_service.dart';
import 'flutter_harness_agent_options.dart';
import 'flutter_harness_capabilities.dart';
import 'location/location_resolver.dart';
import 'network/network_context_provider.dart';
import 'package_info/app_info.dart';
import 'package_info/package_info_hosted_service.dart';

/// The default context-window token budget for the Flutter harness agent.
const int defaultFlutterHarnessMaxContextWindowTokens = 1050000;

/// The default per-response output token budget for the Flutter harness agent.
const int defaultFlutterHarnessMaxOutputTokens = 128000;

/// Registers a Flutter harness agent and its device-capability services.
extension FlutterHarnessServiceCollectionExtensions on ServiceCollection {
  /// Registers the Flutter device-capability services and an [AIAgent] backed
  /// by [ChatClient.asHarnessAgent].
  ///
  /// The [configure] callback selects which capabilities are included (safe-core
  /// temporal, connectivity, app info, and device info on by default; location,
  /// detailed network info, and the wake-lock tool opt-in). For app info and
  /// device info, the corresponding background service
  /// ([PackageInfoHostedService] / [DeviceInfoHostedService]) is registered to
  /// populate the cache at startup.
  ///
  /// Runtime services are registered with `tryAddSingleton`, so instances
  /// registered earlier — including a [ChatClient], [LoggerFactory], or any
  /// capability service — are preserved. The agent resolves its [ChatClient]
  /// from [chatClient], else the keyed service named [chatClientServiceKey],
  /// else the unkeyed [ChatClient].
  ServiceCollection addFlutterHarness({
    int maxContextWindowTokens = defaultFlutterHarnessMaxContextWindowTokens,
    int maxOutputTokens = defaultFlutterHarnessMaxOutputTokens,
    ChatClient? chatClient,
    Object? chatClientServiceKey,
    void Function(FlutterHarnessAgentOptions options)? configure,
  }) {
    final options = FlutterHarnessAgentOptions();
    configure?.call(options);

    tryAddSingleton<LoggerFactory>((_) => NullLoggerFactory.instance);
    tryAddSingleton<Clock>((_) => const Clock());
    tryAddSingleton<ConnectivityMonitor>((_) => ConnectivityMonitor());

    if (options.enableDeviceInfo) {
      tryAddSingleton<DeviceInfo>((_) => DeviceInfo());
      addHostedService<DeviceInfoHostedService>(
        (sp) => DeviceInfoHostedService(
          deviceInfo: sp.getRequiredService<DeviceInfo>(),
          loggerFactory: sp.getRequiredService<LoggerFactory>(),
        ),
      );
    }

    if (options.enableAppInfo) {
      tryAddSingleton<AppInfo>((_) => AppInfo());
      addHostedService<PackageInfoHostedService>(
        (sp) => PackageInfoHostedService(
          appInfo: sp.getRequiredService<AppInfo>(),
          loggerFactory: sp.getRequiredService<LoggerFactory>(),
        ),
      );
    }

    if (options.enableLocation) {
      tryAddSingleton<LocationResolver>((_) => LocationResolver());
    }

    if (options.enableNetworkInfo) {
      tryAddSingleton<NetworkInfoSource>((_) => PluginNetworkInfoSource());
    }

    addSingleton<AIAgent>((sp) {
      final client =
          chatClient ??
          (chatClientServiceKey != null
              ? sp.getRequiredKeyedService<ChatClient>(chatClientServiceKey)
              : sp.getRequiredService<ChatClient>());

      final capabilities = buildFlutterHarnessCapabilities(
        options,
        clock: sp.getRequiredService<Clock>(),
        connectivityMonitor: sp.getRequiredService<ConnectivityMonitor>(),
        deviceInfo: options.enableDeviceInfo
            ? sp.getRequiredService<DeviceInfo>()
            : DeviceInfo(),
        appInfo: options.enableAppInfo
            ? sp.getRequiredService<AppInfo>()
            : AppInfo(),
        locationResolver: options.enableLocation
            ? sp.getRequiredService<LocationResolver>()
            : LocationResolver(),
        networkInfoSource: options.enableNetworkInfo
            ? sp.getRequiredService<NetworkInfoSource>()
            : null,
      );

      options.aiContextProviders = [
        ...?options.aiContextProviders,
        ...capabilities.providers,
      ];
      options.chatOptions ??= ChatOptions();
      options.chatOptions!.tools = [
        ...?options.chatOptions!.tools,
        ...capabilities.tools,
      ];

      return client.asHarnessAgent(
        maxContextWindowTokens,
        maxOutputTokens,
        options: options,
      );
    });

    return this;
  }
}
