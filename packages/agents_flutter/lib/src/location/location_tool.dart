import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';
import 'package:geocoding/geocoding.dart';

import 'coarse_area.dart';
import 'location_source.dart';

/// Creates a tool that returns the device's precise current location.
///
/// Unlike [LocationContextProvider], the tool polls fresh on each call because
/// the model is explicitly asking for the current position. It returns precise
/// coordinates alongside the same coarse area string the provider injects.
/// [resolvePosition] and [reverseGeocode] can be overridden with fakes in
/// tests.
AIFunction createCurrentLocationTool({
  CurrentPositionResolver? resolvePosition,
  ReverseGeocoder? reverseGeocode,
}) {
  final resolve = resolvePosition ?? resolveCurrentPosition;
  final geocode = reverseGeocode ?? placemarkFromCoordinates;

  return AIFunctionFactory.create(
    name: 'get_current_location',
    description:
        'Returns the device\'s current location: precise latitude and '
        'longitude, horizontal accuracy and altitude in metres, and the '
        'approximate place name. Use this when you need exact coordinates '
        'rather than the approximate area in context.',
    returnSchema: const {
      'type': 'object',
      'properties': {
        'latitude': {'type': 'number'},
        'longitude': {'type': 'number'},
        'accuracy': {'type': 'number'},
        'altitude': {'type': 'number'},
        'area': {'type': 'string'},
      },
      'required': ['latitude', 'longitude', 'accuracy', 'altitude'],
      'additionalProperties': false,
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final position = await resolve();
      if (position == null) {
        return 'Location is unavailable. Location services may be disabled or '
            'permission has not been granted.';
      }

      final reading = LocationReading.fromPosition(position);
      String? area;
      try {
        area = formatCoarseAreaFromPlacemarks(
          await geocode(reading.latitude, reading.longitude),
        );
      } catch (_) {
        area = null;
      }

      return {
        'latitude': reading.latitude,
        'longitude': reading.longitude,
        'accuracy': reading.accuracy,
        'altitude': reading.altitude,
        'area': ?area,
      };
    },
  );
}

/// Creates a tool that forward-geocodes a free-text address to coordinates.
///
/// [forwardGeocode] can be overridden with a fake in tests.
AIFunction createGeocodeAddressTool({ForwardGeocoder? forwardGeocode}) {
  final geocode = forwardGeocode ?? locationFromAddress;

  return AIFunctionFactory.create(
    name: 'geocode_address',
    description:
        'Converts a free-text address or place name into latitude and '
        'longitude coordinates.',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'address': {
          'type': 'string',
          'description':
              'The address or place name to geocode, such as '
              '"1600 Amphitheatre Parkway, Mountain View, CA".',
        },
      },
      'required': ['address'],
      'additionalProperties': false,
    },
    returnSchema: const {
      'type': 'object',
      'properties': {
        'latitude': {'type': 'number'},
        'longitude': {'type': 'number'},
      },
      'required': ['latitude', 'longitude'],
      'additionalProperties': false,
    },
    callback: (arguments, {CancellationToken? cancellationToken}) async {
      final address = arguments['address']?.toString().trim();
      if (address == null || address.isEmpty) {
        return 'Provide an address to geocode.';
      }

      try {
        final locations = await geocode(address);
        if (locations.isEmpty) {
          return 'No coordinates were found for: $address';
        }
        final location = locations.first;
        return {'latitude': location.latitude, 'longitude': location.longitude};
      } catch (error) {
        return 'Error geocoding address: $error';
      }
    },
  );
}
