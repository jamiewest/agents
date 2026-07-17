import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/dependency_injection.dart';

import 'connectivity_context_provider.dart';
import 'connectivity_monitor.dart';
import 'connectivity_tool.dart';

/// Registers connectivity context services.
extension ConnectivityContextProviderServiceCollectionExtensions
    on ServiceCollection {
  /// Registers a connectivity monitor, context provider, and optional
  /// connectivity tool.
  ///
  /// A [ConnectivityMonitor] registered before this method is preserved. The
  /// monitor is disposed with the service provider, cancelling its
  /// subscription.
  ServiceCollection addConnectivityContextProvider({
    bool includeConnectivityTool = true,
  }) {
    tryAddSingleton<ConnectivityMonitor>((_) => ConnectivityMonitor());
    addSingleton<AIContextProvider>(
      (services) => ConnectivityContextProvider(
        services.getRequiredService<ConnectivityMonitor>(),
      ),
    );

    if (includeConnectivityTool) {
      addSingleton<AITool>((_) => createConnectivityTool());
    }

    return this;
  }
}

/// Adds connectivity context to [ChatClientAgentOptions].
extension ConnectivityContextProviderChatClientAgentOptionsExtensions
    on ChatClientAgentOptions {
  /// Appends a connectivity provider and, by default, a connectivity tool.
  ///
  /// Existing context providers and tools are retained. The caller supplies
  /// [monitor] — and owns its disposal — because a monitor holds a live
  /// platform subscription; creating one here would leave it unreachable and
  /// leaked. Use `ServiceCollection.addConnectivityContextProvider` when the
  /// service provider should own the monitor's lifetime instead.
  ChatClientAgentOptions addConnectivityContextProvider({
    required ConnectivityMonitor monitor,
    AITool? connectivityTool,
    bool includeConnectivityTool = true,
  }) {
    aiContextProviders = [
      ...?aiContextProviders,
      ConnectivityContextProvider(monitor),
    ];

    if (includeConnectivityTool) {
      chatOptions ??= ChatOptions();
      chatOptions!.tools = [
        ...?chatOptions!.tools,
        connectivityTool ?? createConnectivityTool(),
      ];
    }

    return this;
  }
}
