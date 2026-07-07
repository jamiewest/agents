// ignore_for_file: non_constant_identifier_names

import 'package:agents/agents.dart';
import 'package:agents_flutter/agents_flutter.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';
import 'package:extensions/system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('formatCoarseArea', () {
    test('joins locality, administrative area, and country', () {
      const placemark = Placemark(
        locality: 'Riverside',
        administrativeArea: 'California',
        country: 'United States',
      );

      expect(
        formatCoarseArea(placemark),
        'Riverside, California, United States',
      );
    });

    test('skips blank and whitespace-only fields', () {
      const placemark = Placemark(
        locality: '',
        administrativeArea: '  ',
        country: 'United States',
      );

      expect(formatCoarseArea(placemark), 'United States');
    });

    test('returns null when no usable field is present', () {
      const placemark = Placemark(locality: '   ');

      expect(formatCoarseArea(placemark), isNull);
    });

    test('formatCoarseAreaFromPlacemarks returns null for an empty list', () {
      expect(formatCoarseAreaFromPlacemarks(const []), isNull);
    });

    test('formatCoarseAreaFromPlacemarks picks the first usable placemark', () {
      const placemarks = [
        Placemark(),
        Placemark(locality: 'Riverside', country: 'United States'),
      ];

      expect(
        formatCoarseAreaFromPlacemarks(placemarks),
        'Riverside, United States',
      );
    });
  });

  group('LocationResolver', () {
    test('resolves the coarse area once and caches it', () async {
      var positionCalls = 0;
      var geocodeCalls = 0;
      final resolver = LocationResolver(
        resolvePosition: () async {
          positionCalls++;
          return _position(33.95, -117.39);
        },
        reverseGeocode: (lat, lng) async {
          geocodeCalls++;
          return const [
            Placemark(
              locality: 'Riverside',
              administrativeArea: 'California',
              country: 'United States',
            ),
          ];
        },
      );

      final first = await resolver.ensureArea();
      final second = await resolver.ensureArea();

      expect(first, 'Riverside, California, United States');
      expect(second, same(first));
      expect(resolver.area, 'Riverside, California, United States');
      expect(positionCalls, 1);
      expect(geocodeCalls, 1);
    });

    test('refresh clears the cache and re-resolves', () async {
      final areas = [
        'Riverside, California, United States',
        'Portland, Oregon',
      ];
      var calls = 0;
      final resolver = LocationResolver(
        resolvePosition: () async => _position(0, 0),
        reverseGeocode: (lat, lng) async {
          final area = areas[calls++];
          final parts = area.split(', ');
          return [
            Placemark(
              locality: parts[0],
              administrativeArea: parts.length > 1 ? parts[1] : null,
              country: parts.length > 2 ? parts[2] : null,
            ),
          ];
        },
      );

      expect(
        await resolver.ensureArea(),
        'Riverside, California, United States',
      );
      expect(await resolver.refresh(), 'Portland, Oregon');
      expect(resolver.area, 'Portland, Oregon');
    });

    test('leaves the area unknown when no position is available', () async {
      final resolver = LocationResolver(
        resolvePosition: () async => null,
        reverseGeocode: (lat, lng) async => const [],
      );

      expect(await resolver.ensureArea(), isNull);
      expect(resolver.area, isNull);
    });

    test(
      'caches an unresolved attempt instead of re-acquiring a fix each call',
      () async {
        var positionCalls = 0;
        final resolver = LocationResolver(
          resolvePosition: () async {
            positionCalls++;
            return _position(0, 0);
          },
          reverseGeocode: (lat, lng) async => const [],
        );

        expect(await resolver.ensureArea(), isNull);
        expect(await resolver.ensureArea(), isNull);

        expect(positionCalls, 1);
      },
    );
  });

  group('LocationContextProvider', () {
    test('injects a coarse, coordinate-free location instruction', () async {
      final provider = LocationContextProvider(
        LocationResolver(
          resolvePosition: () async => _position(33.95, -117.39),
          reverseGeocode: (lat, lng) async => const [
            Placemark(
              locality: 'Riverside',
              administrativeArea: 'California',
              country: 'United States',
            ),
          ],
        ),
      );

      final result = await provider.invoking(
        _createInvokingContext(instructions: 'Existing instructions.'),
      );

      expect(result.instructions, startsWith('Existing instructions.\n'));
      expect(
        result.instructions,
        contains('Riverside, California, United States'),
      );
      expect(result.instructions, contains('get_current_location'));
      expect(result.instructions, isNot(contains('33.95')));
      expect(result.instructions, isNot(contains('-117.39')));
      expect(result.messages, isNull);
    });

    test('leaves context untouched when the area is unknown', () async {
      final provider = LocationContextProvider(
        LocationResolver(
          resolvePosition: () async => null,
          reverseGeocode: (lat, lng) async => const [],
        ),
      );

      final result = await provider.invoking(
        _createInvokingContext(instructions: 'Existing instructions.'),
      );

      expect(result.instructions, 'Existing instructions.');
      expect(result.messages, isNull);
    });
  });

  group('get_current_location', () {
    test('returns precise coordinates and the coarse area', () async {
      final tool = createCurrentLocationTool(
        resolvePosition: () async => _position(33.95, -117.39),
        reverseGeocode: (lat, lng) async => const [
          Placemark(locality: 'Riverside', country: 'United States'),
        ],
      );

      final result =
          await tool.invoke(AIFunctionArguments()) as Map<String, Object?>;

      expect(tool.name, 'get_current_location');
      expect(result['latitude'], 33.95);
      expect(result['longitude'], -117.39);
      expect(result['accuracy'], 5.0);
      expect(result['altitude'], 100.0);
      expect(result['area'], 'Riverside, United States');
    });

    test('reports a friendly message when location is unavailable', () async {
      final tool = createCurrentLocationTool(
        resolvePosition: () async => null,
        reverseGeocode: (lat, lng) async => const [],
      );

      final result = await tool.invoke(AIFunctionArguments());

      expect(result, isA<String>());
      expect(result as String, contains('unavailable'));
    });
  });

  group('geocode_address', () {
    test('returns coordinates for the first match', () async {
      final tool = createGeocodeAddressTool(
        forwardGeocode: (address) async => [
          Location(latitude: 37.42, longitude: -122.08, timestamp: _epoch),
        ],
      );

      final result =
          await tool.invoke(
                AIFunctionArguments({'address': '1600 Amphitheatre'}),
              )
              as Map<String, Object?>;

      expect(tool.name, 'geocode_address');
      expect(result['latitude'], 37.42);
      expect(result['longitude'], -122.08);
    });

    test('reports a friendly message when no match is found', () async {
      final tool = createGeocodeAddressTool(
        forwardGeocode: (address) async => const [],
      );

      final result = await tool.invoke(
        AIFunctionArguments({'address': 'nowhere'}),
      );

      expect(result, isA<String>());
      expect(result as String, contains('No coordinates'));
    });
  });

  group('registration', () {
    test('registers the resolver, provider, and both tools', () {
      final services = ServiceCollection()..addLocationContextProvider();
      final serviceProvider = services.buildServiceProvider();

      final resolver = serviceProvider.getRequiredService<LocationResolver>();
      final providers = serviceProvider.getServices<AIContextProvider>();
      final tools = serviceProvider.getServices<AITool>();

      expect(resolver, isA<LocationResolver>());
      expect(providers, hasLength(1));
      expect(
        tools.map((tool) => tool.name),
        containsAll(['get_current_location', 'geocode_address']),
      );
    });

    test('options helper preserves existing providers and tools', () {
      final existingTool = AIFunctionFactory.create(
        name: 'existing_tool',
        callback: (_, {cancellationToken}) async => null,
      );
      final options = ChatClientAgentOptions()
        ..chatOptions = ChatOptions(temperature: 0.25, tools: [existingTool]);

      final returned = options.addLocationContextProvider(
        includeGeocodeTool: false,
      );

      expect(returned, same(options));
      expect(options.aiContextProviders, hasLength(1));
      expect(options.chatOptions!.temperature, 0.25);
      expect(options.chatOptions!.tools!.first, same(existingTool));
      expect(options.chatOptions!.tools!.last.name, 'get_current_location');
    });
  });
}

final _epoch = DateTime.utc(2026, 6, 19);

Position _position(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: _epoch,
  accuracy: 5,
  altitude: 100,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 1,
);

InvokingContext _createInvokingContext({String? instructions}) {
  return InvokingContext(
    _TestAgent(),
    null,
    null,
    AIContext()..instructions = instructions,
  );
}

final class _TestAgent extends AIAgent {
  @override
  Future<AgentSession> createSessionCore({
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSession> deserializeSessionCore(
    dynamic serializedState, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentResponse> runCore(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<AgentResponseUpdate> runCoreStreaming(
    Iterable<ChatMessage> messages, {
    AgentSession? session,
    AgentRunOptions? options,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> serializeSessionCore(
    AgentSession session, {
    Object? jsonSerializerOptions,
    CancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }
}
