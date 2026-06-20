import 'package:geocoding/geocoding.dart';

/// Builds a coarse, cache-friendly area string from a reverse-geocoded
/// [placemark].
///
/// Joins the non-blank locality (city), administrative area (state or region),
/// and country with `, `, e.g. `Riverside, California, United States`. Returns
/// null when none of those fields are present so callers can treat the area as
/// unknown.
///
/// The value is deliberately coarse: it stays stable as the device moves within
/// a city, which keeps an agent's cached prompt prefix warm. Precise
/// coordinates belong in the location tools, not the context provider.
String? formatCoarseArea(Placemark placemark) {
  final parts =
      [placemark.locality, placemark.administrativeArea, placemark.country]
          .map((part) => part?.trim())
          .where((part) => part != null && part.isNotEmpty);

  if (parts.isEmpty) return null;
  return parts.join(', ');
}

/// Returns the first usable coarse area from [placemarks], or null when the
/// list is empty or no placemark yields a non-blank area.
///
/// Reverse geocoding can return an empty list (offline, emulator, or no match),
/// so this is the graceful-degradation point for an unknown area.
String? formatCoarseAreaFromPlacemarks(List<Placemark> placemarks) {
  for (final placemark in placemarks) {
    final area = formatCoarseArea(placemark);
    if (area != null) return area;
  }
  return null;
}
