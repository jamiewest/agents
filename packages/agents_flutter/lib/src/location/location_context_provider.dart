import 'package:agents/agents.dart';
import 'package:extensions/system.dart';

import 'location_resolver.dart';

/// Adds the device's coarse general area to each agent invocation.
///
/// The provider injects only a coarse `City, State, Country` string — never
/// precise coordinates — because instructions land in the cached prompt prefix
/// and a value that changed with every small movement would invalidate that
/// cache. Precise latitude and longitude are available through the
/// `get_current_location` tool. LocationContextProvider supplies the locational
/// frame; tools perform locational actions.
///
/// The area is read from [LocationResolver], which resolves it once and caches
/// it, so the provider performs no per-invocation platform I/O after the first
/// resolve. While the area is unknown — no fix yet, permission not granted, or
/// no network for reverse geocoding — an empty [AIContext] is returned so the
/// cached prefix is left untouched.
final class LocationContextProvider extends AIContextProvider {
  /// Creates a location context provider backed by [resolver].
  LocationContextProvider(this.resolver);

  /// The resolver whose cached coarse area is injected into context.
  final LocationResolver resolver;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async {
    final area = await resolver.ensureArea();
    if (area == null) {
      return AIContext();
    }

    return AIContext()
      ..instructions =
          'Approximate user location: $area. Use this for region, locale, '
          'and timezone-aware answers. Call the get_current_location tool when '
          'you need precise coordinates.';
  }
}
