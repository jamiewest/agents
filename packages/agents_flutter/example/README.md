# agents_flutter example

A single-screen Flutter app that builds a `FlutterHarnessAgent` from an
Anthropic-backed `ChatClient` and runs one turn against it.

The harness supplies compaction, function invocation, and the Flutter
device-capability context providers and tools, so the agent can answer
questions such as "what time is it?" or "am I online?" without extra wiring.

See [`lib/main.dart`](https://github.com/jamiewest/agents/blob/main/packages/agents_flutter/example/lib/main.dart).

## Running it

Copy the example into a Flutter app that depends on `agents_flutter`, then:

```sh
flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
```

## The three pieces

Create the agent — the two positional arguments are the model's context-window
size and per-response output limit, which configure compaction:

```dart
final chatClient = anthropic.AnthropicClient(
  config: anthropic.AnthropicConfig(
    authProvider: anthropic.ApiKeyProvider(apiKey),
  ),
).asChatClient(modelId: 'claude-opus-5');

final agent = chatClient.asFlutterHarnessAgent(
  1000000, // model context-window tokens
  128000,  // model per-response output tokens
  options: FlutterHarnessAgentOptions()..enableWakeLock = true,
);
```

Safe-core capabilities (temporal, connectivity, app info, device info) are on
by default; location, detailed network info, and the wake-lock tool are opt-in.

Create a session once and reuse it so the conversation accumulates:

```dart
final session = await agent.createSession();
```

Run a turn:

```dart
final response = await agent.run(session, null, message: 'What is the date?');
print(response.text);
```
