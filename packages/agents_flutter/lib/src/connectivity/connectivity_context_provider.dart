import 'package:agents/agents.dart';
import 'package:extensions/system.dart';

import 'connectivity_monitor.dart';

/// Adds a concise offline marker to an agent invocation when the device has no
/// network access.
///
/// The marker is emitted only while offline; when online or the state is not
/// yet known, no instructions are added so the cached prompt prefix is left
/// untouched. State is read synchronously from [ConnectivityMonitor], so the
/// provider performs no per-invocation I/O.
final class ConnectivityContextProvider extends AIContextProvider {
  /// Creates a connectivity context provider backed by [monitor].
  ConnectivityContextProvider(this.monitor);

  /// The monitor whose cached state determines the offline marker.
  final ConnectivityMonitor monitor;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    if (!monitor.isOffline) {
      return AIContext();
    }

    return AIContext()
      ..instructions =
          'Network status: offline (no connectivity). Avoid '
          'network-dependent tools and tell the user when an action needs '
          'connectivity to be restored.';
  }
}
