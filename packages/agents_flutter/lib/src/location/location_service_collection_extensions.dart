import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';

import 'location_context_provider.dart';
import 'location_resolver.dart';
import 'location_tool.dart';

/// Registers location context services.
extension LocationContextProviderServiceCollectionExtensions
    on ServiceCollection {
  /// Registers a location resolver, context provider, and optional location
  /// tools.
  ///
  /// A [LocationResolver] registered before this method is preserved. The
  /// resolver is disposed with the service provider.
  ///
  /// Register this after a temporal provider and before a connectivity provider
  /// so the coarse area — which changes rarely — sits between the daily-stable
  /// date and the volatile connectivity marker in the cached prompt prefix.
  ServiceCollection addLocationContextProvider({
    bool includeLocationTool = true,
    bool includeGeocodeTool = true,
  }) {
    tryAddSingleton<LocationResolver>((_) => LocationResolver());
    addSingleton<AIContextProvider>(
      (services) => LocationContextProvider(
        services.getRequiredService<LocationResolver>(),
      ),
    );

    if (includeLocationTool) {
      addSingleton<AITool>((_) => createCurrentLocationTool());
    }
    if (includeGeocodeTool) {
      addSingleton<AITool>((_) => createGeocodeAddressTool());
    }

    return this;
  }
}

/// Adds location context to [ChatClientAgentOptions].
extension LocationContextProviderChatClientAgentOptionsExtensions
    on ChatClientAgentOptions {
  /// Appends a location provider and, by default, the location tools.
  ///
  /// Existing context providers and tools are retained. When [resolver] is
  /// not supplied a new one is created; a resolver holds no live platform
  /// resources (its dispose is a no-op), so an internal instance is safe.
  ///
  /// Append this after a temporal provider and before a connectivity provider
  /// so the coarse area sits between the daily-stable date and the volatile
  /// connectivity marker in the cached prompt prefix.
  ChatClientAgentOptions addLocationContextProvider({
    LocationResolver? resolver,
    AITool? locationTool,
    AITool? geocodeTool,
    bool includeLocationTool = true,
    bool includeGeocodeTool = true,
  }) {
    final effectiveResolver = resolver ?? LocationResolver();

    aiContextProviders = [
      ...?aiContextProviders,
      LocationContextProvider(effectiveResolver),
    ];

    if (includeLocationTool || includeGeocodeTool) {
      chatOptions ??= ChatOptions();
      chatOptions!.tools = [
        ...?chatOptions!.tools,
        if (includeLocationTool) locationTool ?? createCurrentLocationTool(),
        if (includeGeocodeTool) geocodeTool ?? createGeocodeAddressTool(),
      ];
    }

    return this;
  }
}
