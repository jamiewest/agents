import '../../../abstractions/ai_agent.dart';
import '../../../func_typedefs.dart';
import 'background_agents_provider.dart';

/// Options controlling the behavior of [BackgroundAgentsProvider].
class BackgroundAgentsProviderOptions {
  BackgroundAgentsProviderOptions();

  /// Custom instructions provided to the agent for using the background agent
  /// tools.
  ///
  /// Use the `{background_agents}` placeholder to allow the provider to inject
  /// the formatted list of available background agents.
  String? instructions;

  /// Custom function that builds the agent list text to append to
  /// instructions.
  Func<Map<String, AIAgent>, String>? agentListBuilder;

  /// The maximum amount of time the wait tool blocks for a background task to
  /// complete.
  ///
  /// The default is five minutes. The value must be greater than
  /// [Duration.zero] and must not exceed [maximumWaitTimeout]. When the
  /// timeout elapses the tool returns control to the agent and leaves the
  /// background tasks running, so it can be called again to keep waiting.
  Duration waitTimeout = defaultWaitTimeout;

  /// The default value of [waitTimeout].
  static const Duration defaultWaitTimeout = Duration(minutes: 5);

  /// The largest value [waitTimeout] may take.
  ///
  /// Mirrors upstream's `uint.MaxValue - 1` millisecond cap (~49.7 days),
  /// which is also the largest delay a `Timer` can represent when this
  /// package is compiled to JavaScript.
  static const Duration maximumWaitTimeout = Duration(milliseconds: 4294967294);
}
