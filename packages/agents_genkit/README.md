# agents_genkit

[![pub package](https://img.shields.io/pub/v/agents_genkit.svg)](https://pub.dev/packages/agents_genkit)
[![pub points](https://img.shields.io/pub/points/agents_genkit)](https://pub.dev/packages/agents_genkit/score)

Genkit adapters for the [`agents`](https://pub.dev/packages/agents) package.

Wire Genkit flows and tools into the full agent ecosystem — sessions, skills,
context providers, DI — with zero changes to your existing agent code.

## Features

| Class | What it does |
|---|---|
| `GenkitFlowAgent` | Wraps a Genkit `Flow` (or any async function) as a first-class `AIAgent` |
| `GenkitToolsContextProvider` | Injects `AIFunction`s into every invocation via the `AIContextProvider` pipeline |
| `GenkitSkillsSource` | Exposes Genkit `Tool`s as `AgentSkill`s alongside file-based skill sources |
| `addGenkitAgent()` | One-call DI wiring: registers a `ChatClient`, function invocation, and a named `AIAgent` |

## Installation

```yaml
dependencies:
  agents_genkit: ^0.1.0
```

## Usage

### Wrap a Genkit flow as an agent

```dart
import 'package:agents_genkit/agents_genkit.dart';
import 'package:genkit/genkit.dart';

final genkit = Genkit(plugins: [googleAI()]);

final summariseFlow = genkit.defineFlow(
  name: 'summarise',
  fn: (input, _) async {
    final response = await genkit.generate(
      model: googleAI.gemini('gemini-2.5-flash'),
      prompt: 'Summarise this in one sentence: $input',
    );
    return response.text;
  },
);

final agent = GenkitFlowAgent(
  name: 'summariser',
  description: 'Summarises text into one sentence.',
  run: (input) => summariseFlow(input),
);

final session = await agent.createSession();
final response = await agent.run(session, null, message: 'Dart is awesome...');
print(response.text);
```

### Add Genkit tools to an existing agent

`GenkitToolsContextProvider` injects `AIFunction`s at invocation time so any
`ChatClientAgent` gains them without modifying its static configuration.

```dart
import 'package:agents/agents.dart';
import 'package:agents_genkit/agents_genkit.dart';
import 'package:extensions/ai.dart';

// Define a function with the extensions AI abstraction.
final getWeather = AIFunction(
  name: 'get_weather',
  description: 'Returns the current weather for a city.',
  parameters: /* your schema */,
  fn: (args) async => fetchWeather(args['city'] as String),
);

// Inject it into any ChatClientAgent via HarnessAgentOptions.
final options = HarnessAgentOptions(
  aiContextProviders: [
    GenkitToolsContextProvider(functions: [getWeather]),
  ],
);

final agent = chatClient.asHarnessAgent(
  1_000_000,
  8_192,
  options: options,
);
```

### Expose Genkit tools as skills

`GenkitSkillsSource` works with `AggregatingAgentSkillsSource` so Genkit tools
appear alongside your existing file-based skills.

```dart
import 'package:agents/agents.dart';
import 'package:agents_genkit/agents_genkit.dart';
import 'package:genkit/genkit.dart';

final genkit = Genkit(plugins: [googleAI()]);

final calendarTool = genkit.defineTool(
  name: 'create_calendar_event',
  description: 'Creates a Google Calendar event.',
  fn: (input, _) async => createEvent(input),
);

final skillsSource = AggregatingAgentSkillsSource([
  AgentFileSkillsSource(directory: Directory('skills')),
  GenkitSkillsSource(tools: [calendarTool]),
]);

final options = HarnessAgentOptions(agentSkillsSource: skillsSource);
```

### DI registration with addGenkitAgent()

For hosted applications using the `extensions` DI container, `addGenkitAgent()`
mirrors the familiar `addGemma4LiteRtAgent()` pattern.

```dart
import 'package:agents_genkit/agents_genkit.dart';
import 'package:extensions/hosting.dart';
import 'package:genkit/genkit.dart';

void main() async {
  final builder = HostApplicationBuilder();

  builder.services
    .addGenkitAgent(
      model: googleAI.gemini('gemini-2.5-flash'),
      agentName: 'assistant',
      instructions: 'You are a helpful assistant.',
      genkit: Genkit(plugins: [googleAI()]),
    )
    .withInMemorySessionStore();

  await builder.build().run();
}
```

## Additional information

- Part of the [agents](https://github.com/jamiewest/agents) monorepo.
- File issues and feature requests on
  [GitHub](https://github.com/jamiewest/agents/issues).
- See the [`agents`](https://pub.dev/packages/agents) package for the full
  agent session, workflow, and middleware documentation.
