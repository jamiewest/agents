## 1.0.0

Initial release — Dart port of four C# namespaces from the
[Microsoft Agents AI framework](https://github.com/microsoft/agent-framework).

**Abstractions** (`Microsoft.Agents.AI.Abstractions`)

- `AIAgent` — base class for all agents; defines `run`, `runStreaming`,
  `createSession`, `serializeSession`, and `deserializeSession`
- `AgentSession` / `AgentSessionStateBag` — stateful conversation context
  serializable to/from JSON
- `AgentResponse` / `AgentResponseUpdate` — typed wrappers around
  `ChatResponse` / `ChatResponseUpdate`
- `AgentRunOptions` / `AgentRunContext` — per-call options and ambient context
- `DelegatingAIAgent` — base for decorator agents that forward to an inner agent
- `ChatHistoryProvider` / `InMemoryChatHistoryProvider` — pluggable chat
  history persistence
- `AIContextProvider` / `MessageAIContextProvider` — context enrichment hooks
  that inject instructions, messages, and tools before each run

**AI** (`Microsoft.Agents.AI`)

- `ChatClientAgent` — production `AIAgent` backed by any `ChatClient`
  (automatic function-invocation middleware, conversation-id tracking,
  per-service-call history persistence)
- `ChatClientAgentOptions` — fluent configuration for instructions, tools,
  chat options, and history providers
- `AIAgentBuilder` — composable decorator pipeline builder
- `LoggingAgent` — decorator that emits structured `Logger` output at
  debug/trace granularity
- `FunctionInvocationDelegatingAgent` — injects custom middleware around
  every tool call
- `AnonymousDelegatingAIAgent` — lightweight decorator from a lambda
- Extension methods: `ChatClient.asAIAgent`, `ChatClientBuilder.buildAIAgent`,
  `ChatClientBuilder.usePerServiceCallChatHistoryPersistence`
- **Compaction** — `CompactionChatClient`, `CompactionTelemetry`,
  `CompactionGroupKind`, `CompactionTrigger`
- **Evaluation** — `AgentEvaluator`, `EvalCheck`, `CheckResult`,
  `AgentEvaluationExtensions`
- **Skills** — `AgentSkillsProvider`, `AgentSkillsSource`,
  `AgentInMemorySkillsSource`, `AgentFileSkillsSource`,
  `DeduplicatingAgentSkillsSource`, `AgentSkillFrontmatter`,
  `AgentSkillResource`, `AgentSkillScript`
- **Harness** — file store, file access, file memory, todo, sub-agents, agent
  mode, and tool-approval providers for local agent runtimes

**Hosting** (`Microsoft.Agents.AI.Hosting`)

- `HostApplicationBuilderAgentExtensions` — DI registration helpers
- `AgentHostingServiceCollectionExtensions` — service-collection extensions
- `HostedAgentBuilder` / `HostedWorkflowBuilder` — lifecycle-managed agent
  and workflow wiring
- `WorkflowCatalog` — registry for named workflow definitions

**Workflows** (`Microsoft.Agents.AI.Workflows`)

- `Executor` / `Workflow` / `WorkflowContext` — multi-agent orchestration
  engine
- `MessageRouter` / `ProtocolBuilder` / `ProtocolDescriptor` — message routing
  and protocol description
- Checkpointing, observability, in-process execution, and specialised workflow
  sub-areas
