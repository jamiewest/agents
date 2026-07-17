# Porting notes for `packages/agents`

This package is a Dart port of the C# [Microsoft Agents AI framework]
(https://github.com/microsoft/agent-framework) (`dotnet/src/*`). This file is
the **canonical ledger of intentional divergences** from upstream, plus the
folder-to-namespace map and recurring porting gotchas.

**Read this before reporting drift, bugs, or missing APIs.** Anything listed
under "Intentional divergences" or "Verified faithful" must NOT be re-flagged
by reviews or `/drift` runs. When a new deliberate deviation is decided,
append it here (with a date) — do not record it only in session memory.

## Folder → upstream namespace map

| Dart folder (`lib/src/`) | Upstream C# project (`dotnet/src/`) |
|---|---|
| `abstractions/` | `Microsoft.Agents.AI.Abstractions` |
| `ai/` | `Microsoft.Agents.AI` |
| `ai/open_ai/` | `Microsoft.Agents.AI.OpenAI` |
| `workflows/` | `Microsoft.Agents.AI.Workflows` |
| `hosting/` | `Microsoft.Agents.AI.Hosting` |
| `hosting/a2a/` | `Microsoft.Agents.AI.Hosting.A2A` |
| `hosting/open_ai/` | `Microsoft.Agents.AI.Hosting.OpenAI` |
| `a2a/` | `Microsoft.Agents.AI.A2A` |
| `anthropic/` | `Microsoft.Agents.AI.Anthropic` |
| `harness/` | `Microsoft.Agents.AI.Harness` |
| `mcp/` | `Microsoft.Agents.AI.Mcp` |
| `tools/shell/` | `Microsoft.Agents.AI.Tools.Shell` |

**Dart-original (no upstream counterpart — never flag as drift):**

- `gemini/` — Gemini chat client; upstream has no Gemini project.
- `hosting/local/` — in-memory session store; upstream ships store
  implementations as separate providers (CosmosNoSql, Valkey) instead.
- Top-level helpers: `json_stubs.dart`, `activity_stubs.dart`,
  `func_typedefs.dart`, `map_extensions.dart` — explicit stand-ins for C#
  reflection/JSON machinery and delegate types.

**Upstream projects not ported (out of scope by default — confirm with Jamie
before porting):** AGUI, AzureAI.Persistent, CopilotStudio, CosmosNoSql,
Declarative, DevUI, DurableTask, Foundry(+Hosting), GitHub.Copilot,
Hyperlight, LocalCodeAct, Mem0, Purview, Valkey, Workflows.Declarative(.*),
Workflows.Generators, Hosting.AspNetCore, Hosting.AzureFunctions,
Hosting.A2A.AspNetCore, Hosting.AGUI.AspNetCore, Aspire.*.

## Intentional divergences (do NOT re-flag)

- **Magentic orchestration is centralized, not decentralized** (2026-06-19).
  Upstream uses orchestrator + agents-as-executors + TurnTokens + turn-based
  `ChatProtocolExecutor` + `OrchestrationBuilderBase` fan-out. This port uses
  a single re-entrant orchestrator executor (same idiom as `GroupChatHost` /
  `HandoffStartExecutor`) that invokes team agents directly via per-agent
  sessions. Consequently there is no `ResetChatSignal` (uses
  `ResettableExecutor`/session clear), no per-agent fan-out edges, and many
  coordination rounds run per super-step. `ExecutorAgentHarness` (internal,
  upstream Specialized/Magentic) is skipped for the same reason.
- **Workflows `Futures` not ported** (2026-07-03). Its only flag
  (`EnableAgentResponseOutputTaggingAndFiltering`) governs a legacy
  unconditional `AgentResponseEvent` bypass; the port's centralized model
  already routes agent responses through `yieldOutput`/output filter, i.e.
  it behaves like flag=true.
- **Magentic events surface via `yieldOutput`** — PlanCreated / Replanned /
  ProgressLedgerUpdated + manager warnings arrive as
  `WorkflowOutputEvent.data` (no `addEvent` on the executor-facing
  `WorkflowContext`; matches the `AgentResponseEvent` precedent).
  `MagenticPlanReviewResponse` is nullable because the runtime's
  `sendRequest` placeholder does `null as TResponse`.
- **Loop family** (2026-06-18, `ai/harness/loop/`): C# `Continue` renamed
  `proceed` (Dart keyword); `LoopJsonContext` skipped (source-gen);
  `AIJudgeLoopEvaluator` has no generic `ChatResponse<T>` in `extensions` —
  uses `ChatOptions.responseFormat = ChatResponseFormat.forJsonSchema` and
  parses `response.text`, keeping the C# `VERDICT: DONE/MORE` text fallback
  (MORE wins). No upstream loop builder extension exists, so none was added.
- **`DeferredOpenTelemetryChatClient` skipped** — upstream's inert pipeline
  slot that `OpenTelemetryAgent` activates so chat spans emit below FICC.
  The port's `OpenTelemetryAgent` wraps an `OpenTelemetryChatClient` directly
  (different, working design); porting the slot alone is dead code. Revisit
  only as part of an OTel span-layering sync.
- **Skills file-source options keep directory-based drift** —
  `scriptDirectories`/`resourceDirectories`/`resourceSearchDepth` vs upstream
  `SearchDepth`; deliberately not reconciled (2026-07-03).
- **Provider states skipped as derived/non-serializable** (2026-07-03):
  compaction `State` (groups rebuild from chat history) and
  `BackgroundAgentRuntimeState` (in-flight refs; restored tasks rely on
  lost-marking). `ToolApprovalState` persists standing rules ONLY — collected
  or queued in-flight approval content is transient mid-turn state.
- **No runtime reflection anywhere** — upstream reflection/STJ machinery is
  replaced by explicit converters and callbacks:
  `ChatMessageJsonConverter` (abstractions), per-provider
  `toJson`/`stateRehydrator` on `ProviderSessionState`, sentinel
  `*_json_utilities.dart` files mirroring `AgentAbstractionsJsonUtilities`.
  Consequently these upstream types have NO Dart counterpart by design:
  source-gen `*JsonContext` / `*JsonSerializerOptions` classes, and the
  discovery attributes (`MessageHandlerAttribute`, `SendsMessageAttribute`,
  `YieldsOutputAttribute`, `AgentSkillScriptAttribute`,
  `AgentSkillResourceAttribute`) — replaced by explicit registration
  (e.g. `ReflectingExecutor` typed handler registration, inline skill
  builders).
- **Hosting.OpenAI is shelf-based, JSON-backed** (2026-06-19/20, verified
  2026-07-06). No ASP.NET: `shelf` + `shelf_router`, handlers return
  `ApiResult`, routers serialize (mirrors the a2a precedent). Upstream's ~25
  polymorphic `ItemResource`/`ItemParam` subtypes and their converter classes
  collapse into JSON-backed value objects keyed by `type`
  (`responses/models/item_resource.dart`) — so the upstream `Converters/`,
  `Models/`, HttpHandler, and DI-extension types are absorbed, not missing.
  Public surface via `open_ai/open_ai.dart` barrel only (NOT in the global
  `agents.dart` barrel — avoids `Tool`/`Response` name collisions).
  Known-deferred (real backlog, not design): exotic Responses streaming
  event generators (audio/image/reasoning-summary/workflow/MCP/
  function-approval — follow the pattern in
  `responses/models/streaming_response_event.dart`) and chat-completions
  citation annotations (no `extensions/ai` equivalent yet).
- **`ai/open_ai/` is a thin extension layer** — upstream
  `Microsoft.Agents.AI.OpenAI` adapts the .NET OpenAI SDK
  (`ClientResult`/streaming pipeline plumbing such as
  `AsyncStreaming*CollectionResult`, `StreamingUpdatePipelineResponse`,
  `OpenAIResponseClientExtensions`); Dart has no such SDK, chat clients come
  from `extensions`. That plumbing is N/A by design.
- **MCP skill loaders are private and co-located** — upstream's public
  `Skills/Loaders/` types (`AgentMcpSkillArchiveExtractor`,
  `IMcpSkillEntryLoader`, `SkillMdEntryLoader`, `ArchiveFormat`) exist as
  private `_ArchiveEntryLoader`/`_ArchiveFormat`/`_loadSkillMdEntries` inside
  `mcp/agent_mcp_skills_source.dart`. Functionality equivalent; cosmetic
  shape drift only.
- **Anthropic beta features are `betas` parameters** on the client
  extensions rather than a separate `AnthropicBetaServiceExtensions` class.
- **Hosting.OpenAI map-options sync** (2026-07-13, ports upstream's
  2026-07-01/03 refactor: `OpenAI*MapOptions`, `OpenAI*RequestInfo(Builder)`,
  `HostedAgentResponseExecutor`, `ResponseErrorCodes`). Deviations:
  `HostedAgentResponseExecutor` resolves agents via a `ResolveHostedAgent`
  callback instead of keyed DI services, and delegates execution to an
  `AIAgentResponseExecutor` (upstream shares event generation via a
  `ToStreamingResponseAsync` extension; the port's generation lives in the
  executor). `NotSupportedException` maps to `UnsupportedError`;
  `ResponseErrorCodes.mapValidationError` returns a Dart record.
  `AgentReference` is typed; the internal `AgentId`/`AgentIdType` entity
  models are not yet consumed and were not ported.
- **`getService` supertype matching lives in the generic helper**
  (2026-07-13). Dart cannot test a runtime `Type` for assignability, so the
  C# `serviceType.IsInstanceOfType(this)` check cannot be ported to
  `getService(Type)`; the base implementations answer exact `runtimeType`
  and base-type requests only. The keyed generic `getServiceOf<T>` adds the
  supertype match via a `this is T` fallback that runs AFTER the delegation
  chain — so for a base-type request a delegating agent returns its
  innermost agent (pinned by tests), where C# returns the outermost. Do not
  "fix" the ordering without deciding to change those semantics.
- **`AIAgent.currentRunContext` is a plain mutable static** (2026-07-13).
  Upstream uses `AsyncLocal` with a protected setter; Dart has neither, and
  zone-based storage was deliberately not used. `run`/`runStreaming` assign
  it (and re-assign after each streamed update) like upstream, but the value
  does not flow per-async-context and any code can set it.
- **A2A card resolution** maps upstream `A2ACardResolverExtensions` onto
  `extension A2AAgentCardExtensions on A2AAgentCard`
  (`a2a/extensions/a2a_agent_card_extensions.dart`).

## Verified faithful (do NOT re-flag as bugs)

- `ScopeId` `==`/`hashCode` ignores `executorId` for named scopes — upstream
  design; `UpdateKey` adds the strict executor check.
- Two `MessageRouter` classes: the top-level edge router is a Dart-specific
  simplified engine; the `execution/` one mirrors upstream typed dispatch.
- `AgentSessionStateBag.setValue` putIfAbsent+setDeserialized = upstream
  `GetOrAdd`+`SetDeserialized`.
- Custom `_generateUuid` in `a2a_agent_handler` is a correct UUID v4
  (`package:uuid` is not allowlisted).

## Naming conventions (do not flag as API gaps)

- C# `*Async` suffix is dropped: `RunAsync` → `run`, `CreateSessionAsync` →
  `createSession`, `InvokingAsync` → `invoking`, etc.
- C# `IFoo` interfaces are merged into the concrete `Foo` type
  (`IWorkflowContext` → `WorkflowContext`, `ICheckpointStore` →
  `CheckpointStore`, ...). Scanners must strip the `I` before declaring a
  type missing.
- Parameter names are `lowerCamelCase` even when the C# parameter's TYPE
  name is more famous than its name — e.g. the session-serialization
  parameter is `jsonSerializerOptions` (`Object?`-typed), never
  `JsonSerializerOptions`. (A package-wide misnaming of exactly this
  parameter hid behind 34 `non_constant_identifier_names` ignores until
  2026-07-06; do not reintroduce lint suppressions to paper over naming.)

## Porting gotchas

- **Cross-package ripple:** `dart analyze` on `packages/agents` alone does
  NOT catch subclass breaks in dependents. After changing any base contract
  (e.g. `AgentFileStore`), also run `dart analyze` in
  `packages/agents_flutter`. The separately maintained
  [`agents_app`](https://github.com/jamiewest/agents_app) is also a downstream
  consumer and should be checked when preparing a coordinated release
  (`RecordStoreAgentFileStore` broke the app's dart2js build in 2026-07).
- `extensions` `FunctionCallContent` does NOT subtype `ToolCallContent`.
  Tests bridge with
  `class _FunctionToolCall extends ToolCallContent implements
  FunctionCallContent`; runtime checks need the `dynamic` cast idiom.
- Methods that own a lock (e.g. `Pool(1)` write locks in
  `FileAccessProvider`) must be `async` so path-validation `ArgumentError`s
  surface as Future errors — sync throws break
  `expectLater(invoke(...), throws...)` tests.
- State-bag serialization is per-value resilient: non-encodable values are
  skipped with a `dart:developer` log (C# serializes everything via
  reflection; Dart cannot).

## Maintenance

When a `/drift` run or review concludes a difference is deliberate, confirm
with Jamie, then append it to the appropriate section above with a date.
Design decisions in this package are Jamie's: a broken intermediate state is
usually mid-port work-in-progress, not a bug — check the upstream C# source
and ask before restructuring.
