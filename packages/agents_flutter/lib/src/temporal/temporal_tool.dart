import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

import 'local_time_zone.dart';
import 'temporal_formatter.dart';

/// The name of the tool created by [createCurrentTimeTool].
const String currentTimeToolName = 'get_current_time';

/// Creates a tool that returns the current time in an IANA time zone.
///
/// When no `timeZoneId` argument is supplied by the model and [timeZoneId] is
/// null, the device zone is detected once via [resolveLocalTimeZone] and
/// cached. [fallbackTimeZoneId] is used if detection fails.
///
/// TemporalContextProvider supplies the temporal frame. Tools perform temporal
/// actions.
AIFunction createCurrentTimeTool({
  Clock? clock,
  String? timeZoneId,
  String fallbackTimeZoneId = 'America/Los_Angeles',
  LocalTimeZoneResolver? resolveLocalTimeZone,
}) {
  final effectiveClock = clock ?? const Clock();
  final resolver = resolveLocalTimeZone ?? resolveDeviceTimeZone;
  final formatter = TemporalFormatter();
  String? cachedTimeZoneId;

  Future<String> defaultTimeZoneId() async {
    if (timeZoneId != null) return timeZoneId;
    final cached = cachedTimeZoneId;
    if (cached != null) return cached;
    try {
      return cachedTimeZoneId = await resolver();
    } catch (_) {
      return cachedTimeZoneId = fallbackTimeZoneId;
    }
  }

  return AIFunctionFactory.create(
    name: currentTimeToolName,
    description:
        'Returns the current local date and time in an IANA time zone. '
        'Use this for explicit time lookups, especially for a zone other than '
        'the device default zone.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'timeZoneId': {
          'type': 'string',
          'description':
              'Optional IANA time-zone identifier, such as Asia/Tokyo.',
        },
      },
      'additionalProperties': false,
    },
    returnSchema: const {
      'type': 'object',
      'properties': {
        'localDateTime': {'type': 'string'},
        'isoTimestamp': {'type': 'string'},
        'timeZoneId': {'type': 'string'},
      },
      'required': ['localDateTime', 'isoTimestamp', 'timeZoneId'],
      'additionalProperties': false,
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final requestedTimeZoneId = arguments['timeZoneId']?.toString().trim();
      final effectiveTimeZoneId =
          requestedTimeZoneId == null || requestedTimeZoneId.isEmpty
          ? await defaultTimeZoneId()
          : requestedTimeZoneId;

      // A model-supplied zone id can be invalid ("PST", "EST"); report the
      // failure to the model instead of throwing, like the sibling tools.
      try {
        return formatter
            .format(effectiveClock.now(), effectiveTimeZoneId)
            .toJson();
      } catch (error) {
        return 'Error getting current time: unknown time zone '
            '"$effectiveTimeZoneId". Use an IANA identifier such as '
            'Asia/Tokyo. ($error)';
      }
    },
  );
}
