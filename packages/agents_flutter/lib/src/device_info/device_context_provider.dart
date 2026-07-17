import 'package:agents/agents.dart';
import 'package:extensions/system.dart';

import 'device_info.dart';

/// Adds a compact one-line device summary to each agent invocation.
///
/// [DeviceInfo] is gathered once at startup and never changes, so the rendered
/// line is byte-stable across turns and does not invalidate the native KV
/// prefix cache. Emits nothing until the gather completes (a brief window early
/// in the first chat), so it never injects a placeholder.
final class DeviceContextProvider extends AIContextProvider {
  DeviceContextProvider(this._deviceInfo);

  final DeviceInfo _deviceInfo;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final summary = _deviceInfo.summary;
    if (summary == null) return AIContext();
    return AIContext()..instructions = 'Device: $summary';
  }
}
