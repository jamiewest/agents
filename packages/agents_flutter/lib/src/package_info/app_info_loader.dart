import 'package:package_info_plus/package_info_plus.dart';

import 'app_info.dart';

/// Reads platform package metadata from `package_info_plus`.
///
/// Shared by [PackageInfoHostedService] (the DI/hosting path) and
/// [populateAppInfo] (the direct, hostless path) so both load the same
/// fields.
Future<void> loadAppInfo(AppInfo appInfo) async {
  final info = await PackageInfo.fromPlatform();
  appInfo.populate(
    appName: info.appName,
    packageName: info.packageName,
    version: info.version,
    buildNumber: info.buildNumber,
  );
}

/// Loads platform package metadata into [appInfo], swallowing any failure.
///
/// Used by the direct, hostless path ([FlutterHarnessAgent]) where no
/// [PackageInfoHostedService] runs. Returns normally even when loading
/// fails; the `get_app_info` tool then reports the not-available message.
Future<void> populateAppInfo(AppInfo appInfo) async {
  try {
    await loadAppInfo(appInfo);
  } catch (_) {
    // Leave unpopulated; the tool reports "not available yet".
  }
}
