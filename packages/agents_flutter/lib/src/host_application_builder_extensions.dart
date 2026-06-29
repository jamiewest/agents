import 'package:extensions/ai.dart';
import 'package:extensions_flutter/extensions_flutter.dart';

import 'flutter_harness_agent_options.dart';
import 'flutter_harness_service_collection_extensions.dart';

/// Registers a Flutter harness agent from a [HostApplicationBuilder].
extension FlutterHarnessHostApplicationBuilderExtensions
    on HostApplicationBuilder {
  /// Registers the Flutter harness agent and its device-capability services.
  ///
  /// Delegates to [FlutterHarnessServiceCollectionExtensions.addFlutterHarness].
  HostApplicationBuilder addFlutterHarness({
    int maxContextWindowTokens = defaultFlutterHarnessMaxContextWindowTokens,
    int maxOutputTokens = defaultFlutterHarnessMaxOutputTokens,
    ChatClient? chatClient,
    Object? chatClientServiceKey,
    void Function(FlutterHarnessAgentOptions options)? configure,
  }) {
    services.addFlutterHarness(
      maxContextWindowTokens: maxContextWindowTokens,
      maxOutputTokens: maxOutputTokens,
      chatClient: chatClient,
      chatClientServiceKey: chatClientServiceKey,
      configure: configure,
    );
    return this;
  }
}

/// Registers a Flutter harness agent from a [FlutterBuilder].
extension FlutterHarnessFlutterBuilderExtensions on FlutterBuilder {
  /// Registers the Flutter harness agent and its device-capability services.
  ///
  /// Designed for use inside `addFlutter`:
  ///
  /// ```dart
  /// services.addFlutter((flutter) => flutter.useFlutterHarnessAgent(
  ///   configure: (options) => options.enableNetworkInfo = true,
  /// ));
  /// ```
  ///
  /// Delegates to [FlutterHarnessServiceCollectionExtensions.addFlutterHarness].
  FlutterBuilder useFlutterHarnessAgent({
    int maxContextWindowTokens = defaultFlutterHarnessMaxContextWindowTokens,
    int maxOutputTokens = defaultFlutterHarnessMaxOutputTokens,
    ChatClient? chatClient,
    Object? chatClientServiceKey,
    void Function(FlutterHarnessAgentOptions options)? configure,
  }) {
    services.addFlutterHarness(
      maxContextWindowTokens: maxContextWindowTokens,
      maxOutputTokens: maxOutputTokens,
      chatClient: chatClient,
      chatClientServiceKey: chatClientServiceKey,
      configure: configure,
    );
    return this;
  }
}
