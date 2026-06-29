import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'network_context_provider.dart';

/// Creates a tool that returns the device's current local network details.
///
/// Unsupported or unavailable fields are omitted. [networkInfo] can be
/// overridden with a fake in tests.
AIFunction createCurrentNetworkInfoTool({
  NetworkInfo? networkInfo,
  NetworkInfoSource? source,
}) {
  assert(
    networkInfo == null || source == null,
    'Provide either networkInfo or source, not both.',
  );
  final info = source ?? PluginNetworkInfoSource(networkInfo: networkInfo);

  return AIFunctionFactory.create(
    name: 'get_current_network_info',
    description:
        'Returns current local network interface details such as Wi-Fi SSID, '
        'BSSID, IP addresses, subnet mask, gateway IP, and broadcast address. '
        'Use this for local networking, connectivity troubleshooting, LAN '
        'access, or device network configuration.',
    returnSchema: const {
      'type': 'object',
      'properties': {
        'ssid': {'type': 'string'},
        'bssid': {'type': 'string'},
        'ipv4Address': {'type': 'string'},
        'ipv6Address': {'type': 'string'},
        'subnetMask': {'type': 'string'},
        'gatewayIp': {'type': 'string'},
        'broadcastAddress': {'type': 'string'},
      },
      'additionalProperties': false,
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final details = await Future.wait(<Future<MapEntry<String, String>?>>[
        _readNetworkInfo('ssid', info.getWifiName),
        _readNetworkInfo('bssid', info.getWifiBSSID),
        _readNetworkInfo('ipv4Address', info.getWifiIP),
        _readNetworkInfo('ipv6Address', info.getWifiIPv6),
        _readNetworkInfo('subnetMask', info.getWifiSubmask),
        _readNetworkInfo('gatewayIp', info.getWifiGatewayIP),
        _readNetworkInfo('broadcastAddress', info.getWifiBroadcast),
      ]);

      final result = <String, String>{
        for (final detail in details.nonNulls) detail.key: detail.value,
      };
      if (result.isEmpty) {
        return 'Network info is unavailable on this device or platform.';
      }
      return result;
    },
  );
}

Future<MapEntry<String, String>?> _readNetworkInfo(
  String name,
  Future<String?> Function() read,
) async {
  try {
    final value = (await read())?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return MapEntry(name, value);
  } catch (_) {
    return null;
  }
}
