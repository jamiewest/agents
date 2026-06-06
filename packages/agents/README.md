# agents

A Dart port of the
[Microsoft Agents AI framework](https://github.com/microsoft/agent-framework).
Build, compose, and orchestrate AI agents backed by any `ChatClient` — with
sessions, streaming, tool use, compaction, evaluation, and middleware
pipelines.

| C# namespace | Dart layer |
|---|---|
| `Microsoft.Agents.AI.Abstractions` | `abstractions/` |
| `Microsoft.Agents.AI` | `ai/` |
| `Microsoft.Agents.AI.Hosting` | `hosting/` |
| `Microsoft.Agents.AI.Workflows` | `workflows/` |

## Features

- **Provider-agnostic** — works with any `ChatClient` (OpenAI, Azure OpenAI,
  Anthropic, local models, or a custom stub)
- **Stateful sessions** — `AgentSession` persists conversation history, state
  bags, and conversation IDs across turns; serialisable to/from JSON
- **Streaming** — first-class `Stream<AgentResponseUpdate>` support
- **Tool use** — automatic function-invocation middleware; inject custom
  approval or retry logic around every tool call
- **Composable middleware** — `AIAgentBuilder` chains decorators (logging,
  telemetry, evaluation, compaction) with a fluent API
- **Chat history providers** — pluggable `ChatHistoryProvider` for in-memory
  or custom persistence backends
- **AI context providers** — `AIContextProvider` hooks enrich instructions,
  messages, and tools before each agent run
- **Evaluation** — `AgentEvaluator` with named `EvalCheck` assertions
- **Skills** — file-backed and in-memory skill sources with YAML front-matter
- **Multi-agent workflows** — `Executor`, `Workflow`, and `MessageRouter` for
  orchestrating agent pipelines
- **Hosting** — DI / `IHost` integration for lifecycle-managed agents and
  workflows

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  agents: ^1.0.0
```

Then fetch dependencies:

```sh
dart pub get
```

You will also need a `ChatClient` implementation from your AI provider of
choice. The `extensions` package (a transitive dependency) defines the
`ChatClient` abstract type; wrap your provider's SDK in a `ChatClient`
adapter to use it with this package.

## Usage

### Basic agent — single turn

```dart
// Wrap any ChatClient with a system prompt, name, and tools.
final agent = myChatClient.asAIAgent(
  name: 'Assistant',
  instructions: 'You are a concise, helpful assistant.',
);

final session = await agent.createSession();
final response = await agent.run(
  session,
  null,
  CancellationToken.none,
  message: 'What is the capital of France?',
);

print(response.text); // Paris
```

### Multi-turn conversation with a session

`AgentSession` carries chat history and state across runs so you do not
have to manage history manually.

```dart
final session = await agent.createSession();

Future<String> chat(String message) async {
  final response = await agent.run(
    session, null, CancellationToken.none, message: message,
  );
  return response.text ?? '';
}

print(await chat('My name is Ada.'));
print(await chat('What is my name?')); // recalls "Ada" from history
```

### Streaming

```dart
final session = await agent.createSession();

await for (final update in agent.runStreaming(
  session, null, CancellationToken.none,
  message: 'Write me a haiku about Dart.',
)) {
  stdout.write(update.text ?? '');
}
stdout.writeln();
```

### Composing middleware with `AIAgentBuilder`

```dart
final agent = AIAgentBuilder(innerAgent: baseAgent)
  .use(agentFactory: (inner) => LoggingAgent(inner, logger))
  .build();
```

Every call to `agent.run(...)` now passes through `LoggingAgent` before
reaching the underlying `ChatClientAgent`.

### Tool use

```dart
final getWeather = AIFunction.create(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  (Map<String, Object?> args) async {
    final city = args['city'] as String;
    return 'Sunny, 22 °C in $city';
  },
  parameters: [AIFunctionParameter(name: 'city', type: AIFunctionParameterType.string)],
);

final agent = myChatClient.asAIAgent(
  instructions: 'You are a weather assistant.',
  tools: [getWeather],
);
```

The built-in `FunctionInvokingChatClient` middleware resolves tool calls
automatically before returning the final response.

## Additional information

- **Source**: [github.com/jamiewest/agents](https://github.com/jamiewest/agents)
- **Upstream C# framework**:
  [github.com/microsoft/agent-framework](https://github.com/microsoft/agent-framework)
- **Docs**: [learn.microsoft.com/agent-framework](https://learn.microsoft.com/en-us/agent-framework/)
- **Issues**: please file on the
  [GitHub issue tracker](https://github.com/jamiewest/agents/issues)
