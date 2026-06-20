import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extensions/system.dart';

/// Tracks device connectivity by subscribing to change events and caching the
/// latest result.
///
/// Subscribing once and caching keeps platform I/O off the agent's hot path:
/// [ConnectivityContextProvider] reads [isOffline] synchronously on every
/// invocation instead of awaiting a poll. This is the reusable template for
/// other device-state monitors (battery, location, and so on).
final class ConnectivityMonitor implements Disposable {
  /// Creates a monitor and immediately begins tracking connectivity.
  ///
  /// [onChanged] and [checkConnectivity] default to the [Connectivity] plugin
  /// and can be overridden with fakes in tests so no platform channel is hit.
  ConnectivityMonitor({
    Stream<List<ConnectivityResult>>? onChanged,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
  }) : _checkConnectivity =
           checkConnectivity ?? Connectivity().checkConnectivity {
    final stream = onChanged ?? Connectivity().onConnectivityChanged;
    _subscription = stream.listen(_update, onError: (_) {});
    _seed();
  }

  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  late final StreamSubscription<List<ConnectivityResult>> _subscription;

  List<ConnectivityResult>? _latest;

  /// The most recently observed connectivity results, or null until the first
  /// reading arrives.
  List<ConnectivityResult>? get latest =>
      _latest == null ? null : List.unmodifiable(_latest!);

  /// Whether the device is known to be offline.
  ///
  /// True only when the latest reading is empty or every interface reports
  /// [ConnectivityResult.none]. An unknown state (no reading yet) is treated
  /// as online to avoid false offline warnings.
  bool get isOffline {
    final latest = _latest;
    if (latest == null) return false;
    return latest.isEmpty ||
        latest.every((result) => result == ConnectivityResult.none);
  }

  Future<void> _seed() async {
    try {
      _update(await _checkConnectivity());
    } catch (_) {
      // Leave state unknown; treated as online until a change arrives.
    }
  }

  void _update(List<ConnectivityResult> results) => _latest = results;

  @override
  void dispose() {
    _subscription.cancel();
  }
}
