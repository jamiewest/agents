import 'package:agents/agents.dart';
import 'package:extensions/ai.dart';
import 'package:extensions/system.dart';

/// An [AIContextProvider] that injects a fixed list of [AIFunction]s into
/// every agent invocation.
///
/// Use this to add Genkit-backed functions to an existing [ChatClientAgent]
/// without modifying its base configuration. The functions are merged with any
/// tools already present in the [AIContext] by the provider pipeline.
///
/// Example:
/// ```dart
/// final provider = GenkitToolsContextProvider(
///   functions: [getWeatherFunction, getTimezoneFunction],
/// );
/// // Pass to HarnessAgentOptions.aiContextProviders or
/// // ChatClientAgentOptions.aiContextProviders.
/// ```
class GenkitToolsContextProvider extends AIContextProvider {
  /// Creates a [GenkitToolsContextProvider] with the given [functions].
  GenkitToolsContextProvider({required List<AIFunction> functions})
      : _functions = List.unmodifiable(functions);

  final List<AIFunction> _functions;

  @override
  Future<AIContext> provideAIContext(
    InvokingContext context, {
    CancellationToken? cancellationToken,
  }) async =>
      AIContext()..tools = _functions;
}
