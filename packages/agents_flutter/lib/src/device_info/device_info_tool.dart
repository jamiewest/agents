import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'device_info.dart';

/// Builds the `get_device_info` tool bound to [deviceInfo].
///
/// The data is gathered once at startup by `DeviceInfoHostedService`; this tool
/// just reads the cached values, so it returns instantly with no plugin call.
AIFunction createGetDeviceInfoTool(DeviceInfo deviceInfo) {
  return AIFunctionFactory.create(
    name: 'get_device_info',
    description:
        'Returns information about the device this app is running on, '
        'such as the device model, operating system name and version, and '
        'hardware details. Takes no arguments.',
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      return deviceInfo.describe();
    },
  );
}
