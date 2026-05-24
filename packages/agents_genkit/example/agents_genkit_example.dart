// ignore_for_file: avoid_print

import 'package:agents/agents.dart';
import 'package:agents_genkit/agents_genkit.dart';

/// Demonstrates the three main integration points of agents_genkit:
///
/// 1. [GenkitFlowAgent] — wrap a Genkit flow as an [AIAgent].
/// 2. [GenkitSkillsSource] — surface Genkit tools as agent skills.
/// 3. [addGenkitAgent] — one-call DI registration.
void main() async {
  // ── 1. GenkitFlowAgent ───────────────────────────────────────────────────

  final agent = GenkitFlowAgent(
    name: 'echo-agent',
    description: 'Echoes every message back in upper case.',
    // Replace with a real Genkit flow in production:
    //   run: (input) => myFlow(input),
    run: (input) async => input.toUpperCase(),
  );

  final session = await agent.createSession();
  final response = await agent.run(session, null, message: 'hello genkit');
  print('GenkitFlowAgent response: ${response.text}');
  // → GenkitFlowAgent response: HELLO GENKIT

  // ── 2. GenkitSkillsSource ────────────────────────────────────────────────

  // In practice, obtain tools from a configured Genkit instance:
  //
  //   final genkit = Genkit(plugins: [googleAI()]);
  //   final tool = genkit.defineTool(name: 'my-tool', ...);
  //   final source = GenkitSkillsSource(tools: [tool]);
  //
  // Here we skip the live model setup and just print the class name.
  print('GenkitSkillsSource: ${GenkitSkillsSource(tools: [])}');

  // ── 3. addGenkitAgent (DI) ───────────────────────────────────────────────
  //
  // Register a Genkit-backed agent in a hosted application:
  //
  //   import 'package:extensions/dependency_injection.dart';
  //   import 'package:extensions/hosting.dart';
  //   import 'package:genkit/genkit.dart';
  //
  //   final builder = HostApplicationBuilder();
  //   builder.services
  //     .addGenkitAgent(
  //       model: googleAI.gemini('gemini-2.5-flash'),
  //       agentName: 'assistant',
  //       genkit: Genkit(plugins: [googleAI()]),
  //     )
  //     .withInMemorySessionStore();
  //   await builder.build().run();
}
