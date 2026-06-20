import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Resolves the device's current position, or null when a fix is unavailable.
///
/// Wrapping the plugin call in a function type keeps the platform channel out
/// of [LocationResolver] and the location tools, so tests can inject a
/// deterministic resolver instead of touching a real device.
typedef CurrentPositionResolver = Future<Position?> Function();

/// Reverse-geocodes a coordinate into candidate placemarks.
///
/// Defaults to `geocoding`'s [placemarkFromCoordinates]; override with a fake
/// in tests.
typedef ReverseGeocoder =
    Future<List<Placemark>> Function(double latitude, double longitude);

/// Forward-geocodes a free-text address into candidate locations.
///
/// Defaults to `geocoding`'s [locationFromAddress]; override with a fake in
/// tests.
typedef ForwardGeocoder = Future<List<Location>> Function(String address);

/// The default [CurrentPositionResolver], backed by `geolocator`.
///
/// Reads the position only when permission has *already* been granted — it
/// never calls `Geolocator.requestPermission()`, so it cannot pop an OS
/// permission dialog in the middle of an agent turn. Returns null when location
/// services are disabled, permission is denied, or the read fails, so every
/// caller degrades gracefully to an unknown location.
///
/// Host-app requirements (a library cannot configure these): the embedding app
/// must declare `NSLocationWhenInUseUsageDescription` in `Info.plist` (iOS) and
/// the `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` permissions in
/// `AndroidManifest.xml` (Android), and must obtain runtime location permission
/// before relying on the provider or tools.
Future<Position?> resolveCurrentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}

/// A coarse, serializable snapshot of a position reading.
///
/// Keeps the plugin's [Position] type out of tool and formatter logic while
/// exposing the fields a model needs for precise location answers.
final class LocationReading {
  /// Creates a reading with explicit coordinate fields.
  const LocationReading({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.timestamp,
  });

  /// Builds a reading from a `geolocator` [position].
  factory LocationReading.fromPosition(Position position) => LocationReading(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    altitude: position.altitude,
    timestamp: position.timestamp,
  );

  /// Degrees north of the equator.
  final double latitude;

  /// Degrees east of the prime meridian.
  final double longitude;

  /// Estimated horizontal accuracy of the reading, in metres.
  final double accuracy;

  /// Altitude above sea level, in metres.
  final double altitude;

  /// The instant the reading was taken.
  final DateTime timestamp;
}
