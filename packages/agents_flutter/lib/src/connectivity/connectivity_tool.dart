import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

/// Creates a tool that returns the device's current network connectivity.
///
/// Unlike [ConnectivityContextProvider], the tool polls fresh on each call
/// because the model is explicitly asking for the current status.
/// [checkConnectivity] can be overridden with a fake in tests.
AIFunction createConnectivityTool({
  Future<List<ConnectivityResult>> Function()? checkConnectivity,
}) {
  final check = checkConnectivity ?? Connectivity().checkConnectivity;

  return AIFunctionFactory.create(
    name: 'get_connectivity',
    description:
        'Returns the device\'s current network connectivity status. '
        'Reports the active connection type(s): wifi, mobile, ethernet, '
        'vpn, bluetooth, or none (offline).',
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      try {
        final results = await check();
        if (results.isEmpty ||
            results.every((result) => result == ConnectivityResult.none)) {
          return 'No network connection (offline).';
        }
        final types = results
            .where((result) => result != ConnectivityResult.none)
            .map((result) => result.name)
            .join(', ');
        return 'Connected via: $types';
      } catch (error) {
        return 'Error checking connectivity: $error';
      }
    },
  );
}
