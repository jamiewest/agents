import 'package:package_info_plus/package_info_plus.dart';

import 'app_info.dart';

/// Loads platform package metadata into [appInfo], swallowing any failure.
///
/// Shared by [PackageInfoHostedService] (the DI/hosting path) and the direct,
/// hostless path ([FlutterHarnessAgent]). Returns normally even when loading
/// fails; the `get_app_info` tool then reports the not-available message.
Future<void> populateAppInfo(AppInfo appInfo) async {
  try {
    appInfo.info = await PackageInfo.fromPlatform();
  } catch (_) {
    // Leave unpopulated; the tool reports "not available yet".
  }
}
