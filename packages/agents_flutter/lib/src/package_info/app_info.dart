library;

import 'package:package_info_plus/package_info_plus.dart';

/// Holds the app's package metadata, loaded once at startup.
///
/// Populated by [PackageInfoHostedService] during host startup and read by the
/// `get_app_info` tool. Registered as a singleton so the writer and the tool
/// share the same instance. [info] is `null` until the hosted service has run.
class AppInfo {
  /// The loaded package metadata, or `null` until startup loading completes.
  PackageInfo? info;
}
