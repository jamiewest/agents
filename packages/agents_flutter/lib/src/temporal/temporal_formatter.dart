import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

bool _timeZonesInitialized = false;

void _ensureTimeZonesInitialized() {
  if (_timeZonesInitialized) return;
  time_zone_data.initializeTimeZones();
  _timeZonesInitialized = true;
}

final class TemporalValue {
  const TemporalValue({
    required this.localDate,
    required this.isoDate,
    required this.localDateTime,
    required this.isoTimestamp,
    required this.timeZoneId,
  });

  /// The human-readable local date, e.g. `Thursday, June 11, 2026`.
  ///
  /// Stable within a calendar day, which keeps prompt-prefix caches warm.
  final String localDate;

  /// The ISO-8601 calendar date, e.g. `2026-06-11`.
  final String isoDate;

  /// The human-readable local date and time, e.g.
  /// `Thursday, June 11, 2026, 2:14 PM`.
  final String localDateTime;

  /// The ISO-8601 timestamp with offset, e.g. `2026-06-11T14:14:00-07:00`.
  final String isoTimestamp;

  /// The IANA time-zone identifier used to render this value.
  final String timeZoneId;

  Map<String, Object?> toJson() => {
    'localDateTime': localDateTime,
    'isoTimestamp': isoTimestamp,
    'timeZoneId': timeZoneId,
  };
}

final class TemporalFormatter {
  TemporalFormatter()
    : _humanFormat = DateFormat('EEEE, MMMM d, y, h:mm a', 'en_US'),
      _dateFormat = DateFormat('EEEE, MMMM d, y', 'en_US');

  final DateFormat _humanFormat;
  final DateFormat _dateFormat;

  TemporalValue format(DateTime instant, String timeZoneId) {
    _ensureTimeZonesInitialized();

    final location = _getLocation(timeZoneId);
    final local = time_zone.TZDateTime.from(instant, location);

    return TemporalValue(
      localDate: _dateFormat.format(local),
      isoDate: _formatIsoDate(local),
      localDateTime: _humanFormat.format(local),
      isoTimestamp: _formatIsoTimestamp(local),
      timeZoneId: timeZoneId,
    );
  }

  time_zone.Location _getLocation(String timeZoneId) {
    try {
      return time_zone.getLocation(timeZoneId);
    } on time_zone.LocationNotFoundException {
      throw ArgumentError.value(
        timeZoneId,
        'timeZoneId',
        'Unknown IANA time-zone identifier.',
      );
    }
  }

  String _formatIsoDate(time_zone.TZDateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${value.year.toString().padLeft(4, '0')}-'
        '${twoDigits(value.month)}-'
        '${twoDigits(value.day)}';
  }

  String _formatIsoTimestamp(time_zone.TZDateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absoluteOffset = offset.abs();
    final offsetHours = twoDigits(absoluteOffset.inHours);
    final offsetMinutes = twoDigits(absoluteOffset.inMinutes.remainder(60));

    return '${value.year.toString().padLeft(4, '0')}-'
        '${twoDigits(value.month)}-'
        '${twoDigits(value.day)}T'
        '${twoDigits(value.hour)}:'
        '${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}'
        '$sign$offsetHours:$offsetMinutes';
  }
}
