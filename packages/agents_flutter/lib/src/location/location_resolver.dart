import 'package:extensions/system.dart';
import 'package:geocoding/geocoding.dart';

import 'coarse_area.dart';
import 'location_source.dart';

/// Resolves the device's coarse general area once and caches it.
///
/// Modeled on the temporal time-zone resolver, not a live position stream:
/// `Geolocator.getPositionStream` keeps the GPS radio sampling, a battery and
/// privacy cost a passive change stream never had. Instead a single fix is
/// taken on first use, reverse-geocoded to a coarse `City, State, Country`
/// string, and cached so [LocationContextProvider] can read [area]
/// synchronously off the agent's hot path.
///
/// Implements [Disposable] so it disposes uniformly with other device-state
/// services; there is no subscription to release, so disposal is a no-op.
final class LocationResolver implements Disposable {
  /// Creates a resolver backed by injectable platform functions.
  ///
  /// [resolvePosition] and [reverseGeocode] default to the `geolocator` and
  /// `geocoding` implementations and can be overridden with fakes in tests so
  /// no platform channel is hit.
  LocationResolver({
    CurrentPositionResolver? resolvePosition,
    ReverseGeocoder? reverseGeocode,
  }) : _resolvePosition = resolvePosition ?? resolveCurrentPosition,
       _reverseGeocode = reverseGeocode ?? placemarkFromCoordinates;

  final CurrentPositionResolver _resolvePosition;
  final ReverseGeocoder _reverseGeocode;

  String? _area;
  bool _resolved = false;

  /// The cached coarse area, e.g. `Riverside, California, United States`, or
  /// null until the first successful resolve.
  String? get area => _area;

  /// Resolves the coarse area once and caches the result, returning the cached
  /// value on later calls.
  ///
  /// Resolution reads the current position and reverse-geocodes it. The attempt
  /// is cached whether or not it yields an area, so a failure — services
  /// disabled, permission not granted, no network, or no match — is *not*
  /// retried on every invocation (that would re-acquire a GPS fix on the agent
  /// hot path). Call [refresh] to retry once a fix or network becomes
  /// available.
  Future<String?> ensureArea() async {
    if (_resolved) return _area;
    return _resolve();
  }

  /// Clears the cache and re-resolves the coarse area.
  ///
  /// Use this to refresh the area after the device has travelled; the provider
  /// itself never re-resolves automatically, to stay off the hot path.
  Future<String?> refresh() {
    _resolved = false;
    _area = null;
    return _resolve();
  }

  Future<String?> _resolve() async {
    try {
      final position = await _resolvePosition();
      if (position != null) {
        final placemarks = await _reverseGeocode(
          position.latitude,
          position.longitude,
        );
        _area = formatCoarseAreaFromPlacemarks(placemarks);
      }
    } catch (_) {
      // Leave the area unknown; refresh() can retry.
    }
    _resolved = true;
    return _area;
  }

  @override
  void dispose() {}
}
