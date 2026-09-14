# Porting notes for `packages/agents`

This package is a Dart port of the C# [Microsoft Agents AI framework]
(https://github.com/microsoft/agent-framework) (`dotnet/src/*`). This file is
the **canonical ledger of intentional divergences** from upstream, plus the
folder-to-namespace map and recurring porting gotchas.

**Read this before reporting drift, bugs, or missing APIs.** Anything listed
under "Intentional divergences" or "Verified faithful" must NOT be re-flagged
by reviews or `/drift` runs. When a new deliberate deviation is decided,
append it here (with a date) — do not record it only in session memory.

## Upstream sync state

The newest upstream commit touching `dotnet/src` that a drift sync has
reviewed (ported or deliberately skipped):

`upstream-sync: 7a82595cbd9e2efb06356ea81f6a6e4640e537b8 2026-09-14`

This line is machine-read by `/drift` and by
`.github/workflows/upstream-watch.yml` — keep the `upstream-sync: <sha> <date>`
format intact. Every drift sync must advance it to the newest `dotnet/src`
commit it reviewed, in the same commit as the ported changes.

## Folder → upstream namespace map

| Dart folder (`lib/src/`) | Upstream C# project (`dotnet/src/`) |
|---|---|
| `abstractions/` | `Microsoft.Agents.AI.Abstractions` |
| `ai/` | `Microsoft.Agents.AI` |
| `ai/open_ai/` | `Microsoft.Agents.AI.OpenAI` |
| `workflows/` | `Microsoft.Agents.AI.Workflows` |
| `hosting/` | `Microsoft.Agents.AI.Hosting` |
| `hosting/local/` | `Microsoft.Agents.AI.Hosting` (`Local/`) |
| `hosting/a2a/` | `Microsoft.Agents.AI.Hosting.A2A` |
| `hosting/open_ai/` | `Microsoft.Agents.AI.Hosting.OpenAI` |
| `a2a/` | `Microsoft.Agents.AI.A2A` |
| `anthropic/` | `Microsoft.Agents.AI.Anthropic` |
| `harness/` | `Microsoft.Agents.AI.Harness` |
| `mcp/` | `Microsoft.Agents.AI.Mcp` |
| `tools/shell/` | `Microsoft.Agents.AI.Tools.Shell` |

**Dart-original (no upstream counterpart — never flag as drift):**

- `gemini/` — Gemini chat client; upstream has no Gemini project.
- Top-level helpers: `json_stubs.dart`, `activity_stubs.dart`,
  `func_typedefs.dart`, `map_extensions.dart` — explicit stand-ins for C#
  reflection/JSON machinery and delegate types.

**Upstream projects not ported (out of scope by default — confirm with Jamie
before porting):** AGUI, AgentHooks (new 2026-08-19, agent-hooks
interception contract — not yet triaged with Jamie), AzureAI.Persistent,
CopilotStudio, CosmosNoSql, Declarative, DevUI, DurableTask,
Foundry(+Hosting), GitHub.Copilot, Hosting.AzureStorage (new 2026-08-20,
Azure Blob session persistence), Hyperlight, LocalCodeAct, Mem0, Purview,
Valkey, Workflows.Declarative(.*), Workflows.Generators,
Hosting.AspNetCore, Hosting.AzureFunctions, Hosting.A2A.AspNetCore,
Hosting.AGUI.AspNetCore, Aspire.*.

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
  `MagenticPlanReviewResponse` is nullable: originally forced, because the
  runtime's `sendRequest` placeholder did `null as TResponse`. As of
  2026-07-31 the placeholder is `ExternalResponse.pending`, which no longer
  forces null into `TResponse`, so the port's
  `RequestPort<MagenticPlanReviewRequest, MagenticPlanReviewResponse?>` is now
  a free choice rather than a workaround — left as-is pending a decision.
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
- **Checkpoint wire values use a type-id converter registry** (2026-07-31,
  `workflows/checkpointing/wire_marshaller.dart`). Checkpointing serializes
  pending message payloads to JSON text, so payloads outside the JSON model
  (chat messages, for example) cannot round-trip on their own. With no
  reflection to fall back on, `WireMarshaller` carries a static
  `valueConverters` map of `WireValueConverter` (`toWire`/`fromWire`) keyed by
  the payload's `runtimeType.toString()` — the same type id already stored in
  `JsonWireSerializedValue.typeId`, so the converter that serialized a value
  is the one that revives it. Payloads already inside the JSON model need no
  entry and pass through untouched. Same reflection-free idiom as
  `ChatMessageJsonConverter` and the per-provider `stateRehydrator`, except
  the registry is process-global rather than per-run or per-instance:
  registration is a host bootstrap step, and two payload types whose
  `runtimeType.toString()` collides would collide here too.

- **`InvocableFunctionBypassingChatClient` not ported** (2026-08-13). Upstream
  works around .NET's `FunctionInvokingChatClient` terminating its loop when a
  declaration-only (frontend) call appears alongside invocable (backend) calls,
  returning the backend calls unexecuted. Its entire strip/store gate keys off
  `FunctionCallContent.InformationalOnly`, which `extensions` 0.6.0 does not
  have — and the Dart FICC has no such concept and does not reproduce the
  behavior: a declaration-only call falls into `_invokeFunction`'s not-found
  path and the loop continues. There is nothing to detect and nothing to work
  around, so the class, the `EnableInvocableFunctionBypassing` option, and the
  `UseInvocableFunctionBypassing` builder extension are all skipped. Revisit
  only if `extensions` gains an informational-call marker.
- **`ApprovalResponseBindingChatClient` records requests without a snapshot**
  (2026-08-13). Upstream stores a defensive clone of each surfaced
  `ToolApprovalRequestContent` so a later mutation of the caller-visible
  instance cannot change the recorded tool call used for binding. `extensions`
  has no concrete tool call type carrying a function name and arguments —
  `FunctionCallContent` does not subtype `ToolCallContent`, and the
  `ToolCallContent` subclasses are code-interpreter / MCP / image-generation /
  web-search only — so the recorded call cannot be rebuilt. Requests are
  recorded as-is. Rebinding itself is unaffected: it reuses the recorded
  instance rather than constructing one.
- **Approval decorators no-op without a session** (2026-08-13). Both
  `ApprovalNotRequiredFunctionBypassingChatClient` (formerly
  `NonApprovalRequiredFunctionBypassingChatClient`, renamed to follow upstream)
  and `ApprovalResponseBindingChatClient` are installed by default by
  `withDefaultAgentMiddleware`, matching upstream's opt-out
  `Disable*` flags. The port's bypassing client previously threw a `StateError`
  when there was no ambient `AIAgent.currentRunContext` session; default-on
  makes that a breaking trap for any direct chat-client use outside an agent
  run, so it now warns once and passes through, as upstream does. The warning
  goes to the supplied `LoggerFactory` when there is one and to
  `dart:developer` `log()` otherwise (upstream always has an `ILoggerFactory`).
- **Two `withDefaultAgentMiddleware` implementations** (2026-08-13, known
  duplication rather than a design). Upstream has one internal
  `ChatClientExtensions.WithDefaultAgentMiddleware`; the port has a public
  `ChatClient.withDefaultAgentMiddleware` extension AND a private
  `ChatClientAgent._withDefaultAgentMiddleware`, and they have drifted — only
  the agent's copy installs `MessageInjectingChatClient`. This predates the
  approval-decorator work; both copies were updated together there. Reconcile
  onto the extension when either is next touched, and keep them in sync until
  then. Tests that assert pipeline nesting must drive `ChatClientAgent`, since
  that is the path that runs in production.
- **Isolation key provider follows upstream's rename** (2026-08-13).
  `SessionIsolationKeyProvider.getSessionIsolationKey` became
  `AgentIsolationKeyProvider.getIsolationKey`, matching upstream's broadening
  of the contract from sessions to all agent-owned resources (sessions, A2A
  tasks, and anything else needing the same boundary).
  `IsolationKeyScopedTaskStore` is ported alongside it; because the Dart
  `A2ATaskStore` contract is only `save`/`load` and keys by `A2ATask.id` — no
  list query, no separate store key — scoping the task id is what scopes the
  store key, where upstream scopes an explicit `taskId` parameter and leaves
  `AgentTask.Id` bare. `contextId` is scoped as upstream does, and the task is
  cloned rather than mutated because the A2A server reuses the instance for
  live event notification.

- **Feature-usage bitmask / `AgentFrameworkUserAgentPolicy` not ported**
  (2026-08-25, upstream #7709). Upstream stamps an `agent-framework-dotnet`
  User-Agent segment plus a feature-usage bitmask onto .NET
  `System.ClientModel` pipeline requests, driven by assembly-attribute
  reflection and a `FeatureDeclaration` analyzer across every project. None
  of that surface exists in Dart (no shared client pipeline, no assembly
  reflection); N/A by design, do not flag the missing `Shared/FeatureUsage`
  types.
- **MCP Tasks-extension migration deferred** (2026-08-25, upstream #7774
  rewrote `McpClientTaskExtensions`/`McpTaskOptions`/
  `TaskAwareMcpClientAIFunction` against the 2026-07-28 Tasks extension via
  SDK primitives — `CallToolAsTaskAsync`, typed `tasks/get`, per-call task
  handles). `package:mcp_dart` (2.4.x) instead drives that extension
  transparently inside `McpClient.callTool` and keeps those primitives
  private, so upstream's manual poller (stuck-poll caps, input-request caps,
  remote-cancellation timeout) has nothing public to build on. The port
  keeps `listAgentToolsWithTaskSupport` on the legacy SEP-2663 augmentation
  path for `taskSupport == 'required'` tools. Revisit when mcp_dart exposes
  task call handles (and then also adopt upstream's
  `listAgentToolsWithTasks` rename).
- **A2A streaming artifact updates not applicable** (2026-08-25, upstream
  #7722 added `ArtifactStreamWriter` and routed streaming runs through the
  task lifecycle or one aggregated message). The Dart `package:a2a` executor
  seam is non-streaming (`execute` + event bus; no `ExecuteStreamingAsync`),
  so the port's `A2AAgentHandler` never had the one-message-per-update bug:
  it runs non-streaming and already publishes a single aggregated message or
  task events keyed off `continuationToken`. Upstream's writer becomes
  relevant only if the handler is restructured onto `runStreaming` — a
  redesign, ask Jamie first.
- **Hosting.OpenAI `Response` does not echo request sampling fields** —
  follows from the JSON-backed-value-objects divergence above: upstream's
  logprobs-preservation fix (2026-08-24, #5860) adds `Logprobs` echo fields
  the port's slim `Response`/`CreateResponse` models never carried
  (alongside `temperature`, `top_p`, `max_tool_calls`, …; unmodeled request
  fields remain readable via `CreateResponse.raw`). Not a missing port.
- **`BackgroundAgentsProvider.releaseSession`** (2026-08-25, ports upstream
  #7602 `ReleaseSessionAsync`). Deviations: no `SyncRoot` locking (single
  isolate — atomicity between awaits is inherent); `infiniteReleaseTimeout`
  (−1 ms) mirrors `Timeout.InfiniteTimeSpan`; upstream's unobserved-fault
  observer continuations are unnecessary because
  `BackgroundAgentRuntimeTask.completion` already captures errors.
- **`RoutePersistingRoutingChatClient` is self-contained** (2026-08-25,
  ports upstream #7641). Upstream extends `Microsoft.Extensions.AI`'s
  `RoutingChatClient` (`RoutingContext`/`SelectClientAsync` seam);
  `package:extensions` has no routing base, so the Dart client implements
  `ChatClient` directly with the same per-session persisted-route
  semantics. `AgentSessionRoutingState` stays unexported, like upstream's
  internal type. The companion upstream change making
  `AIAgent.RunAsync` async (restoring the previous run context via
  `AsyncLocal` flow) has no Dart counterpart — `currentRunContext` is a
  plain static (see above) with no restore semantics.
- **Skill-discovery symlink hardening uses `typeSync`, not attributes**
  (2026-08-25, ports upstream #7540). Upstream's
  `IsLinkOrReparsePointOrInaccessible`/`SafeEnumerateDirectories` map onto
  `_isLinkOrInaccessible` (`FileSystem.typeSync(followLinks: false)`,
  fail-closed on `FileSystemException`) and `_safeListDirectory`. Resource
  and script escape protection remains the pre-existing
  canonicalize-plus-prefix boundary check rather than upstream's
  per-segment reparse-point walk — equivalent outcome (canonicalize
  resolves links), different mechanism.

- **Line numbering is published on `AgentFileStore`** (2026-09-14, ports
  upstream #7671). `searchFilesAsync` gains a base implementation plus a
  `findMatchingFilesAsync` narrowing hook, and `splitLines`/`scanContent`
  become the published numbering primitives, so grep and the line editor
  cannot drift. Deviations: Dart has no `protected`, so
  `findMatchingFilesAsync` is a plain overridable public method documented as
  the override hook; upstream's `internal static FileEditor` is already public
  here, so `splitLinesKeepEnds`/`sliceLines`/`trimLineTerminator`/
  `lineContentLength` are public statics on it rather than internal. BREAKING,
  as upstream: `FileSearchMatch.line` now carries the line's terminator, and
  line numbers change on content containing a lone `\r` or a trailing newline.
- **A2A hosting streaming split not applicable** (2026-09-14, upstream #7998
  merged the streaming and non-streaming `A2AAgentHandler` paths and added an
  `aggregateTaskUpdates` toggle driven by the request's `ReturnImmediately`,
  plus an `AgentEventQueueExtensions.AddArtifactAsync` metadata shim). The
  Dart `package:a2a` executor seam is non-streaming (`execute` + event bus;
  no `ExecuteStreamingAsync`), the same reason recorded for #7722 above, so
  there is no `StreamTaskUpdatesAsync` counterpart and nothing for the toggle
  to select: the port always aggregates. The portable half — emitting a
  terminal task carrying the result instead of one stuck in `working` — is
  ported as part of #8032 below. The metadata shim is an A2A-SDK version
  workaround with no Dart equivalent. Revisit only if the handler is
  restructured onto `runStreaming`.
- **`AgentRunMode` selects the A2A artifact, not a background flag**
  (2026-09-14, ports upstream #8032). `disallowBackground`/
  `allowBackgroundIfSupported`/`allowBackgroundWhen`/`shouldRunInBackground`
  become `returnMessage`/`returnTask`/`returnTaskWhen`/`shouldReturnTask`, and
  the run mode — not the response's `continuationToken` — now decides whether
  a new message is answered with an `AgentMessage` or an `AgentTask`;
  `AgentRunOptions.allowBackgroundResponses` is no longer set by the handler,
  and task continuations no longer consult the mode. Deviation: on the port's
  non-streaming seam, `returnTask` over a run that already finished emits
  `submitted` → artifact → `completed` (upstream's `AggregateTaskUpdatesAsync`
  shape) rather than leaving a task in `working`. BREAKING rename of the
  public `AgentRunMode` surface.
- **Skill paths are revalidated immediately before use** (2026-09-14, ports
  upstream #8151). `AgentFileSkillPathScope` (configured discovery root +
  skill directory) is threaded through discovery and carried by
  `AgentFileSkillResource`/`AgentFileSkillScript`, which call
  `AgentFileSkillPathValidator.validateForUse` before reading or running.
  Deviation: containment is enforced by the pre-existing canonicalize-plus-
  prefix boundary check (canonicalize resolves links, so a skill directory
  swapped for a link after discovery resolves outside the recorded prefix)
  rather than upstream's per-segment reparse-point walk from the root — the
  same mechanism difference already recorded for #7540 above. The discovery
  methods on `AgentFileSkillsSource` (public here, private upstream) change
  signature to carry the scope.
- **MCP skill archives are ZIP-only** (2026-09-14, ports upstream #8290).
  `_ArchiveFormat` loses `tar`/`tarGz`; gzip is rejected by signature before
  any MIME-type or URL hint is consulted, the tar/gzip media types and the
  `.tar`/`.tar.gz`/`.tgz` URL hints are gone, and extraction throws
  `UnsupportedError` for anything but ZIP. BREAKING for servers that served
  tar archives.
- **Hosting.OpenAI storage is scoped by isolation key** (2026-09-14, ports
  upstream #8146). Adds `IsolationKeyResolver`,
  `IsolationKeyScopedConversationStorage` and
  `IsolationKeyScopedAgentConversationIndex`, using the same escaped
  `{key}::{id}` prefix as `IsolationKeyScopedAgentSessionStore`, and scopes
  the `InMemoryResponsesService` response/conversation keys directly as
  upstream does. Deviations: upstream resolves the key per request from
  ASP.NET claims through request-scoped DI and wires the decorators in
  `EndpointRouteBuilderExtensions`; the port's shelf routers take `storage`
  and `index` as parameters, so `addOpenAIConversations` wraps the in-memory
  defaults when an `AgentIsolationKeyProvider` is registered (strict, so a
  host that configured isolation never silently falls back to a shared
  namespace) and a host mounting its own storage wraps it the same way. The
  ASP.NET endpoint wiring and the conversation-index cache bounding have no
  counterpart.
- **Responses client-function forwarding is opt-in** (2026-09-14, ports
  upstream #7844). `OpenAIResponsesMapOptions.dangerouslyAllowClientFunctionTools`
  selects `mapClientFunctionTools` as the default `runOptionsFactory`, which
  forwards well-formed client function declarations as
  `ChatClientAgentRunOptions.chatOptions.tools` and still rejects every other
  tool entry and unsupported setting; `hasToolChoice` keeps a `tool_choice`
  with no `ChatToolMode` equivalent from slipping through. Deviation:
  `package:extensions` has no `AIFunctionFactory.createDeclaration`, so the
  port subclasses the existing `AIFunctionDeclaration` directly as
  `ClientAIFunctionDeclaration` (carrying `strict` in
  `additionalProperties`) instead of wrapping a factory-produced declaration.
- **Hosted-workflow `includeWorkflowOutputsInResponse` not ported**
  (2026-09-14, upstream #8020 threads that flag from
  `HostedWorkflowBuilderExtensions.AddAsAIAgent` into
  `Workflow.AsAIAgent`). The port's `asAIAgent`/`WorkflowHostAgent` has no
  such parameter — workflow outputs already flow through `yieldOutput` per
  the Magentic divergence above — and the port's `addAsAIAgent` registers a
  keyed agent rather than resolving the workflow and wrapping it, so there is
  nothing to thread the flag through. Revisit if `WorkflowHostAgent` gains an
  output-gating option.

## Verified faithful (do NOT re-flag as bugs)

- `ScopeId` `==`/`hashCode` ignores `executorId` for named scopes — upstream
  design; `UpdateKey` adds the strict executor check.
- Two `MessageRouter` classes: the top-level edge router is a Dart-specific
  simplified engine; the `execution/` one mirrors upstream typed dispatch.
- `AgentSessionStateBag.setValue` putIfAbsent+setDeserialized = upstream
  `GetOrAdd`+`SetDeserialized`.
- Custom `_generateUuid` in `a2a_agent_handler` is a correct UUID v4
  (`package:uuid` is not allowlisted).
- Upstream's public-API analyzer baselines (2026-09-14, #7935) are
  `PublicAPI.{Shipped,Unshipped}.txt` build files with no Dart counterpart;
  likewise the xunit/dependency bumps (#8202) and the `Shared/Workflows`
  sample runner overload (#7913), which lives in sample infrastructure rather
  than a ported project.
- Upstream's 2026-08 removal of AGUI special cases in `ChatClientAgent`
  (#7741) needs no port — the AGUI provider-name checks were never ported
  (AGUI is out of scope). Likewise the camelCase tool-argument description
  fix (#7731) was already in the port's harness providers, and the
  broadened telemetry-serialization catch (#7612) has no counterpart
  because `WorkflowTelemetryContext` is a no-op stub here.

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
