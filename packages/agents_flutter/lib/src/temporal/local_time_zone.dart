import 'package:flutter_timezone/flutter_timezone.dart';

/// Resolves an IANA time-zone identifier for the current device.
///
/// Wrapping the plugin call in a function type keeps the platform channel out
/// of [TemporalContextProvider] and the temporal tool, so tests can inject a
/// deterministic resolver instead of touching a real device.
typedef LocalTimeZoneResolver = Future<String> Function();

/// The default [LocalTimeZoneResolver], backed by `flutter_timezone`.
///
/// Returns the device's IANA identifier, e.g. `America/Los_Angeles`.
Future<String> resolveDeviceTimeZone() async {
  final info = await FlutterTimezone.getLocalTimezone();
  return info.identifier;
}
