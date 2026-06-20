import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/system.dart';

import 'local_time_zone.dart';
import 'temporal_formatter.dart';

/// Adds the current date and time zone to each agent invocation.
///
/// The provider injects the date only — never the clock time — because
/// instructions land in the cached prompt prefix and a value that changed every
/// minute would invalidate that cache on every turn. Precise time-of-day is
/// available through the `get_current_time` tool. TemporalContextProvider
/// supplies the temporal frame; tools perform temporal actions.
///
/// The generated instructions are transient and are not added to conversation
/// history.
final class TemporalContextProvider extends AIContextProvider {
  /// Creates a temporal context provider backed by [clock].
  ///
  /// When [timeZoneId] is null the device IANA zone is detected once via
  /// [resolveLocalTimeZone] and cached. [fallbackTimeZoneId] is used if
  /// detection fails.
  TemporalContextProvider({
    Clock? clock,
    this.timeZoneId,
    this.fallbackTimeZoneId = 'America/Los_Angeles',
    LocalTimeZoneResolver? resolveLocalTimeZone,
  }) : clock = clock ?? const Clock(),
       _resolveLocalTimeZone = resolveLocalTimeZone ?? resolveDeviceTimeZone,
       _formatter = TemporalFormatter();

  /// The clock used to generate invocation-scoped temporal context.
  final Clock clock;

  /// An explicit IANA time-zone override, or null to detect the device zone.
  final String? timeZoneId;

  /// The IANA zone used when [timeZoneId] is null and detection fails.
  final String fallbackTimeZoneId;

  final LocalTimeZoneResolver _resolveLocalTimeZone;
  final TemporalFormatter _formatter;

  String? _cachedTimeZoneId;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final zone = await _effectiveTimeZoneId();
    final value = _formatter.format(clock.now(), zone);

    return AIContext()
      ..instructions =
          'Temporal context:\n'
          '- Current local date: ${value.localDate}\n'
          '- Current ISO date: ${value.isoDate}\n'
          '- Time zone: ${value.timeZoneId}\n'
          '- Use this date when resolving relative date phrases such as today, '
          'tomorrow, yesterday, this weekend, and next Monday. Call the '
          'get_current_time tool when you need the current time of day.';
  }

  /// Resolves the effective IANA zone, caching device detection after the
  /// first call so no platform I/O occurs on later invocations.
  Future<String> _effectiveTimeZoneId() async {
    if (timeZoneId != null) return timeZoneId!;
    final cached = _cachedTimeZoneId;
    if (cached != null) return cached;

    String resolved;
    try {
      resolved = await _resolveLocalTimeZone();
    } catch (_) {
      resolved = fallbackTimeZoneId;
    }
    return _cachedTimeZoneId = resolved;
  }
}
