import 'package:extensions/extensions.dart';

import '../logged_background_service.dart';
import 'device_info.dart';
import 'device_info_gatherer.dart';

/// Gathers device information at startup and populates [DeviceInfo].
///
/// Runs as a [BackgroundService] so its plugin query happens off the host
/// startup path and never delays the first frame; the `get_device_info` tool
/// reports "not available yet" in the brief window before it completes. Any
/// plugin failure is logged and swallowed.
final class DeviceInfoHostedService extends LoggedBackgroundService {
  DeviceInfoHostedService({
    required this.deviceInfo,
    required super.loggerFactory,
  }) : super(serviceName: 'DeviceInfoHostedService');

  final DeviceInfo deviceInfo;

  @override
  Future<void> executeLogged(CancellationToken stoppingToken) async {
    try {
      final fields = await gatherDeviceInfoFields();
      deviceInfo.populate(fields);
      logger.logInformation('device info ready: ${fields.length} fields');
    } catch (e) {
      logger.logError('failed to gather device info', error: e);
    }
  }
}
