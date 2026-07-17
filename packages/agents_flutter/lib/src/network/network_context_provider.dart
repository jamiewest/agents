import 'package:agents/agents.dart';
import 'package:extensions/system.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Reads local network information.
///
/// This keeps provider and tool behavior testable without depending on
/// platform channels in unit tests.
abstract interface class NetworkInfoSource {
  /// Obtains the Wi-Fi network name.
  Future<String?> getWifiName();

  /// Obtains the Wi-Fi BSSID.
  Future<String?> getWifiBSSID();

  /// Obtains the Wi-Fi IPv4 address.
  Future<String?> getWifiIP();

  /// Obtains the Wi-Fi IPv6 address.
  Future<String?> getWifiIPv6();

  /// Obtains the Wi-Fi subnet mask.
  Future<String?> getWifiSubmask();

  /// Obtains the Wi-Fi gateway IP address.
  Future<String?> getWifiGatewayIP();

  /// Obtains the Wi-Fi broadcast address.
  Future<String?> getWifiBroadcast();
}

// coverage:ignore-start
/// [NetworkInfoSource] backed by the `network_info_plus` plugin.
final class PluginNetworkInfoSource implements NetworkInfoSource {
  /// Creates a plugin-backed network info source.
  PluginNetworkInfoSource({NetworkInfo? networkInfo})
    : _networkInfo = networkInfo ?? NetworkInfo();

  final NetworkInfo _networkInfo;

  @override
  Future<String?> getWifiName() => _networkInfo.getWifiName();

  @override
  Future<String?> getWifiBSSID() => _networkInfo.getWifiBSSID();

  @override
  Future<String?> getWifiIP() => _networkInfo.getWifiIP();

  @override
  Future<String?> getWifiIPv6() => _networkInfo.getWifiIPv6();

  @override
  Future<String?> getWifiSubmask() => _networkInfo.getWifiSubmask();

  @override
  Future<String?> getWifiGatewayIP() => _networkInfo.getWifiGatewayIP();

  @override
  Future<String?> getWifiBroadcast() => _networkInfo.getWifiBroadcast();
}
// coverage:ignore-end

/// Adds available device network details to each agent invocation.
///
/// The provider reads the platform network fields in parallel and omits any
/// values that are unavailable or unsupported on the current platform.
///
/// The Flutter harness does not register this provider — only the
/// `get_current_network_info` tool — because it performs six platform-channel
/// reads on every turn and injects volatile values (SSID, addresses) into
/// instructions, which invalidates the model's cached prompt prefix. Compose
/// it manually only when ambient network context is worth that cost.
final class NetworkContextProvider extends AIContextProvider {
  /// Creates a network context provider backed by [networkInfo].
  NetworkContextProvider({NetworkInfo? networkInfo, NetworkInfoSource? source})
    : assert(
        networkInfo == null || source == null,
        'Provide either networkInfo or source, not both.',
      ),
      source = source ?? PluginNetworkInfoSource(networkInfo: networkInfo);

  /// The network info source.
  final NetworkInfoSource source;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final details = await Future.wait(<Future<MapEntry<String, String>?>>[
      _readDetail('Wi-Fi SSID', source.getWifiName),
      _readDetail('IPv4 address', source.getWifiIP),
      _readDetail('IPv6 address', source.getWifiIPv6),
      _readDetail('Subnet mask', source.getWifiSubmask),
      _readDetail('Gateway IP', source.getWifiGatewayIP),
      _readDetail('Broadcast address', source.getWifiBroadcast),
    ]);

    final availableDetails = details.nonNulls.toList(growable: false);
    if (availableDetails.isEmpty) {
      return AIContext();
    }

    return AIContext()
      ..instructions =
          'Network context:\n'
          '${availableDetails.map((entry) => '- ${entry.key}: ${entry.value}').join('\n')}\n'
          '- Use these details only for local networking, connectivity '
          'troubleshooting, LAN access, or device network configuration.';
  }

  Future<MapEntry<String, String>?> _readDetail(
    String label,
    Future<String?> Function() read,
  ) async {
    try {
      final value = (await read())?.trim();
      if (value == null || value.isEmpty) {
        return null;
      }
      return MapEntry(label, value);
    } catch (_) {
      return null;
    }
  }
}
