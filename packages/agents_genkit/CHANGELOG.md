## 0.1.0

- Initial release.
- `GenkitFlowAgent`: wraps any `Future<String> Function(String)` — including a
  Genkit `Flow` — as a fully-featured `AIAgent` with session support, streaming,
  and context-provider integration.
- `GenkitToolsContextProvider`: injects a fixed list of `AIFunction`s into every
  agent invocation via the `AIContextProvider` pipeline.
- `GenkitSkillsSource`: exposes Genkit `Tool`s as `AgentSkill`s; composes with
  `AggregatingAgentSkillsSource` alongside file-based skill sources.
- `addGenkitAgent()`: single-call DI extension on `ServiceCollection` that wires
  a `GenkitChatClient` with function invocation and registers a named `AIAgent`.
