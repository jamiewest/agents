import 'package:agents/agents.dart';
import 'package:extensions_genkit/extensions_genkit.dart';
import 'package:genkit/genkit.dart';

/// Extension methods for registering a Genkit-backed AI agent with a
/// [ServiceCollection].
extension GenkitAgentServiceCollectionExtensions on ServiceCollection {
  /// Registers a Genkit-backed [AIAgent] and returns a [HostedAgentBuilder]
  /// for further configuration (tools, session store, etc.).
  ///
  /// [model] is the Genkit [ModelRef] to use (e.g. `googleAI.gemini(...)`).
  /// [agentName] is the keyed service name used to resolve the agent.
  /// [genkit] is an optional pre-configured [Genkit] instance; when provided
  /// it is registered as the [Genkit] singleton. Otherwise the caller must
  /// register [Genkit] separately before building the service provider.
  ///
  /// Example:
  /// ```dart
  /// services
  ///   .addGenkitAgent(
  ///     model: googleAI.gemini('gemini-2.5-flash'),
  ///     agentName: 'assistant',
  ///     genkit: Genkit(plugins: [googleAI()]),
  ///   )
  ///   .withAITools([getWeatherTool])
  ///   .withInMemorySessionStore();
  /// ```
  HostedAgentBuilder addGenkitAgent({
    required ModelRef model,
    String agentName = 'genkit-agent',
    String? instructions,
    String? description,
    List<AITool> tools = const [],
    bool withInMemorySessionStore = true,
    ServiceLifetime lifetime = ServiceLifetime.singleton,
    Genkit? genkit,
  }) {
    addGenkitChatClient(model: model, genkit: genkit).useFunctionInvocation();

    final builder = addAIAgent(
      agentName,
      lifetime,
      instructions: instructions,
      description: description,
    );

    if (tools.isNotEmpty) builder.withAITools(tools);
    if (withInMemorySessionStore) builder.withInMemorySessionStore();
    return builder;
  }
}
