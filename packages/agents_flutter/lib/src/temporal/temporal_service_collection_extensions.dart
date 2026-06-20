import 'package:agents/agents.dart';
import 'package:clock/clock.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';

import 'temporal_context_provider.dart';
import 'temporal_tool.dart';

/// Registers temporal context services.
extension TemporalContextProviderServiceCollectionExtensions
    on ServiceCollection {
  /// Registers a clock, temporal context provider, and optional current-time
  /// tool.
  ///
  /// A [Clock] registered before this method is preserved. When [timeZoneId]
  /// is null the device IANA zone is detected and cached.
  ServiceCollection addTemporalContextProvider({
    String? timeZoneId,
    bool includeCurrentTimeTool = true,
  }) {
    tryAddSingleton<Clock>((_) => const Clock());
    tryAddSingleton<TemporalContextProvider>(
      (services) => TemporalContextProvider(
        clock: services.getRequiredService<Clock>(),
        timeZoneId: timeZoneId,
      ),
    );
    addSingleton<AIContextProvider>(
      (services) => services.getRequiredService<TemporalContextProvider>(),
    );

    if (includeCurrentTimeTool) {
      addSingleton<AITool>(
        (services) => createCurrentTimeTool(
          clock: services.getRequiredService<Clock>(),
          timeZoneId: timeZoneId,
        ),
      );
    }

    return this;
  }
}

/// Adds temporal context to [ChatClientAgentOptions].
extension TemporalContextProviderChatClientAgentOptionsExtensions
    on ChatClientAgentOptions {
  /// Appends a temporal provider and, by default, a current-time tool.
  ///
  /// Existing context providers and tools are retained.
  ChatClientAgentOptions addTemporalContextProvider({
    Clock? clock,
    TemporalContextProvider? provider,
    AITool? currentTimeTool,
    bool includeCurrentTimeTool = true,
    String? timeZoneId,
  }) {
    final effectiveClock = clock ?? provider?.clock ?? const Clock();
    final effectiveTimeZoneId = provider?.timeZoneId ?? timeZoneId;
    final effectiveProvider =
        provider ??
        TemporalContextProvider(
          clock: effectiveClock,
          timeZoneId: effectiveTimeZoneId,
        );

    aiContextProviders = [...?aiContextProviders, effectiveProvider];

    if (includeCurrentTimeTool) {
      chatOptions ??= ChatOptions();
      chatOptions!.tools = [
        ...?chatOptions!.tools,
        currentTimeTool ??
            createCurrentTimeTool(
              clock: effectiveClock,
              timeZoneId: effectiveTimeZoneId,
            ),
      ];
    }

    return this;
  }
}
