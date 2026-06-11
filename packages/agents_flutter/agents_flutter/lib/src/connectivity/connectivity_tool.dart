import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

/// Returns the device's current network connectivity status.
final getConnectivityTool = AIFunctionFactory.create(
  name: 'get_connectivity',
  description:
      'Returns the device\'s current network connectivity status. '
      'Reports the active connection type(s): wifi, mobile, ethernet, '
      'vpn, bluetooth, or none (offline).',
  callback: (arguments, {CancellationToken? cancellationToken}) async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none)) {
        return 'No network connection (offline).';
      }
      final types = results
          .where((r) => r != ConnectivityResult.none)
          .map((r) => r.name)
          .join(', ');
      return 'Connected via: $types';
    } catch (e) {
      return 'Error checking connectivity: $e';
    }
  },
);
