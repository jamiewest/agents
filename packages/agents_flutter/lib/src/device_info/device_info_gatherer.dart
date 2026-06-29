import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'device_info.dart';

/// Reads platform device fields from `device_info_plus`.
///
/// Shared by [DeviceInfoHostedService] (the DI/hosting path) and
/// [populateDeviceInfo] (the direct, hostless path) so both gather the same
/// platform-specific fields.
Future<Map<String, String>> gatherDeviceInfoFields() async {
  final plugin = DeviceInfoPlugin();

  if (Platform.isIOS) {
    final i = await plugin.iosInfo;
    return {
      'Device': i.name,
      'Model': i.model,
      'System': '${i.systemName} ${i.systemVersion}',
      'Machine': i.utsname.machine,
      'Physical device': '${i.isPhysicalDevice}',
    };
  }

  if (Platform.isMacOS) {
    final m = await plugin.macOsInfo;
    return {
      'Computer': m.computerName,
      'Model': m.model,
      'System': 'macOS ${m.osRelease}',
      'Architecture': m.arch,
      'Memory': '${(m.memorySize / (1024 * 1024 * 1024)).round()} GB',
    };
  }

  if (Platform.isAndroid) {
    final a = await plugin.androidInfo;
    return {
      'Device': '${a.manufacturer} ${a.model}',
      'System': 'Android ${a.version.release} (API ${a.version.sdkInt})',
      'Physical device': '${a.isPhysicalDevice}',
    };
  }

  if (Platform.isWindows) {
    final w = await plugin.windowsInfo;
    return {
      'Computer': w.computerName,
      'System': w.productName,
      'Cores': '${w.numberOfCores}',
    };
  }

  if (Platform.isLinux) {
    final l = await plugin.linuxInfo;
    return {
      'System': l.prettyName,
      if (l.versionId != null) 'Version': l.versionId!,
    };
  }

  final base = await plugin.deviceInfo;
  return base.data.map((k, v) => MapEntry(k, '$v'));
}

/// Populates [deviceInfo] from the platform, swallowing any plugin failure.
///
/// Used by the direct, hostless path ([FlutterHarnessAgent]) where no
/// [DeviceInfoHostedService] runs. Returns normally even when gathering fails;
/// the `get_device_info` tool then reports the not-available message.
Future<void> populateDeviceInfo(DeviceInfo deviceInfo) async {
  try {
    deviceInfo.populate(await gatherDeviceInfoFields());
  } catch (_) {
    // Leave unpopulated; the tool reports "not available yet".
  }
}
