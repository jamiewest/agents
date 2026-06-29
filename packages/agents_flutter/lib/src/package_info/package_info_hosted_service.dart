import 'package:extensions/extensions.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../logged_background_service.dart';
import 'app_info.dart';

/// Loads the app's package metadata once at startup into [AppInfo].
///
/// Runs as a [BackgroundService] so the platform lookup stays off the host
/// startup path and never delays the first frame. `PackageInfo.fromPlatform()`
/// is fast and tools only run once the user sends a message, so the cached
/// value is ready by the time `get_app_info` reads it.
final class PackageInfoHostedService extends LoggedBackgroundService {
  PackageInfoHostedService({
    required this.appInfo,
    required super.loggerFactory,
  }) : super(serviceName: 'PackageInfoHostedService');

  final AppInfo appInfo;

  @override
  Future<void> executeLogged(CancellationToken stoppingToken) async {
    try {
      final info = await PackageInfo.fromPlatform();
      appInfo.info = info;
      logger.logInformation(
        'app ${info.appName} v${info.version}+${info.buildNumber}',
      );
    } catch (e) {
      logger.logError('failed to load package info', error: e);
    }
  }
}
