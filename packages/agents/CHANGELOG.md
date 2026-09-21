# Changelog

## 3.0.0

Upstream drift sync against `microsoft/agent-framework` `dotnet/src`, covering
everything from `92aec78` (2026-08-25) through `0799f6a` (2026-09-18). Skip
decisions and deviations are recorded in `PORTING.md`.

### Breaking

- **A2A run modes name the artifact they return.** `AgentRunMode.disallowBackground`,
  `allowBackgroundIfSupported` and `allowBackgroundWhen` are now `returnMessage`,
  `returnTask` and `returnTaskWhen`, `shouldRunInBackground` is
  `shouldReturnTask`, and `RunInBackgroundCallback` is `ReturnTaskCallback`.
  `A2AAgentHandler` no longer sets `AgentRunOptions.allowBackgroundResponses`:
  the run mode selects the response shape directly, so a `returnTask` run that
  finishes now answers with a completed task carrying an artifact rather than a
  message, and a `returnMessage` run always answers with one aggregated message.
  Continuations of an existing task stay task responses and do not consult the
  mode. (upstream #8032, with the observable part of #7998)
- **`FileSearchMatch.line` is reported verbatim.** Matching lines keep their own
  terminator (`\r\n`, `\n` or a lone `\r`) instead of having it stripped, so a
  grep result can be reused as a `replace_lines` `new_line` without re-reading
  the file. Patterns are still matched against the line without its terminator,
  so end-anchored patterns behave the same on CRLF content. (upstream #7671)
- **Tool-approval responses must bind to a surfaced request.**
  `ToolApprovalAgent.unwrapAlwaysApproveResponses` and
  `collectApprovalResponsesFromMessages` are replaced by a single
  `bindApprovalResponses` pass. An always-approve response now records a
  standing rule only when the agent actually surfaced the request it answers,
  and the rule derives from the recorded tool call rather than the
  caller-supplied one. (upstream #7111, #8432)
- **MCP skill archives are ZIP-only.** TAR and gzip payloads are no longer
  detected or extracted, and a gzip signature is rejected before any MIME type
  or URL hint is consulted. (upstream #8290)

### Added

- `AIAgent.asChatClient(...)` exposes an agent as a `ChatClient`, stateless by
  default or bound to a session, with a single conversation id it both reports
  and accepts. (upstream #7687)
- `file_access_read_lines` reads a 1-based inclusive line range, each line
  prefixed with its number and a tab, numbered by the same split
  `file_access_grep` and `file_access_replace_lines` use. `FileLineEdit` gains
  an optional `expected_line` that rejects an edit landing on a changed line.
  `AgentFileStore` gains a default `searchFilesAsync` over a new
  `findMatchingFilesAsync` hook, plus published `splitLines` and `scanContent`
  primitives. (upstream #7671)
- `AgentFileSkillPathScope` and `AgentFileSkillPathValidator` revalidate a
  discovered skill resource or script against its trusted discovery root
  immediately before it is read or run, rejecting a path swapped for a link
  after discovery. (upstream #8151)
- MCP skill index entries may carry a `sha256:` digest, verified against the
  decoded archive bytes before extraction. (upstream #8404)
- `IsolationKeyResolver` plus isolation-key-scoped conversation storage and
  agent-conversation index scope the OpenAI hosting storage per caller, so one
  caller cannot resolve, list or delete another's conversations or responses.
  (upstream #8146)
- `OpenAIResponsesMapOptions.dangerouslyAllowClientFunctionTools` forwards
  client-supplied function declarations as run-option tools while still
  rejecting other tool types and unsupported settings. (upstream #7844)
- `BackgroundAgentsProviderOptions.waitTimeout` bounds
  `BackgroundAgents_WaitForFirstCompletion`; on timeout the tasks keep running
  and the tool can be called again. Defaults to five minutes. (upstream #7911)
- `AgentModeProviderOptions.disableModeSetTool` / `disableModeGetTool` omit the
  corresponding built-in tool while keeping mode state and instructions, and
  `setMode` gains `disableNotification`. (upstream #8458)
- `OpenTelemetryAgent.defaultSourceName` exposes the default telemetry source
  name so consumers need not hardcode it. (upstream #7815)

### Changed

- Recognized SKILL.md frontmatter fields must use their exact lowercase
  spelling and must not repeat; either rejects the skill instead of silently
  changing which value it exposes. Metadata keys are compared
  case-insensitively, keeping the first value and spelling with a warning.
  (upstream #8430)
- `ApprovalResponseBindingChatClient` no longer treats an approval request
  replayed in the caller's history as proof the framework requested it. Calls
  that already carry a result, and calls to tools that require no approval,
  pass through; a request id that surfaces two different calls binds neither.
  (upstream #8375)
- Function-invocation middleware works on per-run and per-request copies of the
  caller's options instead of mutating them, wraps idempotently, and wraps tools
  added or replaced later in the same run. (upstream #8402, partial — see
  `PORTING.md`)
- `ChatClientAgent` no longer pins constructor tools onto
  `FunctionInvokingChatClient.additionalTools`; they are already merged into the
  per-run `ChatOptions`. (upstream #8531)
- Persistent PowerShell shell sessions clear `$LASTEXITCODE` before each
  command, so a stale exit code from an earlier command is no longer reported.
  (upstream #8259)
- `extensions` is now `^0.7.1`.

## 2.0.0

- **Breaking: `streamAsync` and `resumeStreamAsync` now return a live run.**
  Both used to drive the workflow to quiescence before returning, so the
  returned `StreamingRun` was already finished and its `outgoingEvents` was
  complete. They now return as soon as the run is open and drive it in the
  background. Observe progress with `StreamingRun.watchStreamAsync()`; reading
  `outgoingEvents` immediately after the await yields only the events produced
  so far. External responses sent via `sendResponseAsync` (and messages via
  `trySendMessageAsync`) resume the run.
  - In `ExecutionMode.offThread` (the default) every event is published the
    moment it is created, including outputs yielded part-way through an
    executor invocation — streamed agent updates now surface live. In
    `ExecutionMode.lockstep` events are still batched and published together
    after each superstep.
  - `watchStreamAsync` replays the events already recorded before switching to
    the live tail, so a watcher that subscribes late — even after the run has
    ended — still observes the full sequence.
  - Added `StreamingRun.isCompleted`.
- **Breaking: external responses route by request, not by payload type.**
  `addExternalResponse` previously completed the request and then handed the
  payload to the first executor whose input type accepted it. It now resolves
  the pending `ExternalRequest` by `requestId` (searching joined sub-workflow
  runners too) and delivers the response to the executor that issued it. It
  throws a `StateError` — leaving pending requests untouched — when the
  request id is unknown, already serviced, or the issuing executor does not
  accept the payload type. Workflows that relied on the old loose matching
  must respond with the `ExternalRequest` surfaced by the run's
  `RequestInfoEvent`.
  - `ExternalRequest` gained `sourceExecutorId`, recording the issuing
    executor.
- `WorkflowContext.sendRequest` now returns `ExternalResponse.pending`, an
  explicit placeholder, instead of forcing `null` into `TResponse`. Reading
  `response` on a placeholder throws a `StateError` naming the request and
  port rather than failing with an opaque cast error; the real response
  arrives as a message in a later superstep.
- Added `WireMarshaller.valueConverters`, a registry of `WireValueConverter`s
  keyed by payload type id. Checkpointing serializes pending message payloads
  to JSON text, which fails for payloads outside the JSON model (chat
  messages, for example); hosts can now register a converter to serialize and
  revive those types.
- `AsyncRunHandle` serializes concurrent drive passes, so a caller that
  delivers a message or response while a drive is in flight waits for the
  queued work to be processed. A failure in the initial background drive is
  now reported as a `WorkflowErrorEvent` and ends the run instead of leaving
  stream observers waiting forever.
- **Breaking: requires `extensions: ^0.6.0`**, which changes AI function
  invocation. Reaching `maximumIterationsPerRequest` now issues one more
  provider call with function declarations withheld so the model produces a
  real answer, instead of returning unanswered tool calls; exceeding
  `maximumConsecutiveErrorsPerRequest` now throws (a single failure rethrown
  as-is, several combined into an `AggregateException`) instead of returning a
  partial response; and the limit comparison changed from `>=` to `>`, so a
  limit of `0` surfaces the first tool failure immediately. Also inherits
  `AIContent.annotations` and the completed OpenTelemetry decorator set.
- **Breaking: requires `anthropic_sdk_dart: ^6.0.0`.** Its types appear in
  this package's public API (`AnthropicChatClient.client` and the
  `AnthropicClient` builder extensions), so dependents pinning the SDK
  directly must move to 6.x as well.
- Verified against the current releases of the unchanged constraints, notably
  `mcp_dart` 2.4.0.

## 1.6.0

- Add live shell output reporting: `ShellExecutor.outputEvents` broadcasts
  typed `ShellOutputChunk` values while commands run, local and Docker options
  accept an `onOutput` callback, and persistent shell sessions now capture
  stderr instead of discarding it.

## 1.5.0

- Add `AnthropicChatClient` under `anthropic/`: a `ChatClient` backed by
  Anthropic's Messages API, with client builder extensions and shared
  defaults.
- Add `GeminiChatClient` and `GeminiClient` under `gemini/`: a `ChatClient`
  backed by the Gemini API, with builder extensions and defaults. Handles
  `thoughtSignature` round-tripping on function calls (including the
  documented skip-validation placeholder for replayed calls), strips
  unsupported `additionalProperties` from tool and response schemas, and
  enables server-side tool invocations when mixing Gemini built-in tools
  with function tools.
- Add MCP integration under `mcp/`: `AgentMcpSkillsSource` discovers Agent
  Skills exposed over MCP (`AgentMcpSkill`, `McpSkillIndex`,
  `AgentMcpSkillResource`, plus options), `McpClientTaskExtensions` exposes
  MCP tools as AI functions (`McpClientAIFunction`,
  `TaskAwareMcpClientAIFunction`, `McpTaskOptions`), and the skills
  provider builder gains MCP registration extensions.
- Add sequential and concurrent orchestrations to the workflows engine:
  `SequentialWorkflowBuilder` and `ConcurrentWorkflowBuilder` on the shared
  `OrchestrationBuilderBase`, with `OutputTag` (+ JSON converter),
  `WorkflowOutputEvent` extensions, and checkpoint support for output
  executors in `WorkflowInfo`.
- Add session-store composition under `hosting/`:
  `DelegatingAgentSessionStore`, `IsolationKeyScopedAgentSessionStore`
  (+ options), and `SessionIsolationKeyProvider` for partitioning stored
  sessions by user, tenant, or composite keys.
- Expand OpenAI hosting: `HostedAgentResponseExecutor` routes Responses API
  requests to hosted agents by `agent.name` or `metadata["entity_id"]`,
  with `OpenAIResponseRequestInfo` / `OpenAIChatCompletionRequestInfo`
  request descriptors, per-API map options, `AgentReference`, and
  standardized response error codes.
- Add OpenAI conversion helpers under `ai/open_ai/`: extensions mapping
  `AgentResponse` and `ChatClientAgent` results onto OpenAI wire formats.
- Add auto-approval rules to the tool-approval middleware:
  `ToolApprovalAgentOptions` with ordered `autoApprovalRules` (evaluated
  after standing rules, before prompting the user) and an approve-all rule.
- Expand the file access and file memory providers: new `replace` and
  `replace_lines` editing tools backed by the shared `FileEditor` /
  `FileLineEdit` helpers, `FileStoreEntry` metadata, configurable tool
  names, and read-only / full auto-approval rule presets.
- Add chat-client decorators: `MessageInjectingChatClient` lets external
  code (such as tool delegates) enqueue messages into the function
  invocation loop, and `NonApprovalRequiredFunctionBypassingChatClient`
  strips approval requests for tools that do not require approval,
  re-injecting them pre-approved on the next request.
- Add `BackgroundTaskCompletionLoopEvaluator` (+ options): keeps a
  `LoopAgent` iterating until tracked background tasks complete, with a
  templated feedback message listing the still-running tasks.
- Add skills improvements: a `CachingAgentSkillsSource` decorator
  (+ options), `AgentSkillsSourceContext`, and
  `AgentFileSkillFilterContext` for filtering file-based skills.
- Add evaluation types: `GeneratedEvaluatorRef` (versioned references to
  generated evaluators) and `RubricScore` (typed per-dimension score
  breakdown for rubric evaluators).
- Export `InvokedContext` and `InvokingContext` as standalone libraries
  (previously hidden from the public API) and publicly export
  `ChatMessageJsonConverter`.
- Fix `AIContextProvider.getService` to resolve requests for concrete
  provider types (matching the `runtimeType` idiom used by `AgentSession`
  and `DelegatingAIAgent`); concrete-type lookups previously returned
  `null`, breaking provider resolution in
  `BackgroundTaskCompletionLoopEvaluator` and
  `TodoCompletionLoopEvaluator`.
- Add `anthropic_sdk_dart: ^5.0.0`, `archive: ^4.0.9`, `http: ^1.6.0`, and
  `mcp_dart: ^2.2.1` dependencies; bump `extensions` to `^0.5.0`.

## 1.4.0

- Add loop agents under `harness/loop/`: `LoopAgent` and `LoopAgentOptions`
  run an inner agent repeatedly until an evaluator signals completion, with
  pluggable `LoopEvaluator` strategies — `AIJudgeLoopEvaluator`,
  `CompletionMarkerLoopEvaluator`, `TodoCompletionLoopEvaluator`, and
  `DelegateLoopEvaluator` — plus `LoopContext`, `LoopEvaluation`, and
  `JudgeVerdict` support types.
- Add Magentic multi-agent orchestration to the workflows engine:
  `MagenticWorkflowBuilder`, `MagenticOrchestrator`, the plan-review
  request/response messages, and the progress ledger (ports the upstream
  Magentic manager/orchestrator pattern).
- Add OpenAI-compatible hosting under `hosting/open_ai/`: shelf-based
  routers and handlers for the Chat Completions, Conversations, and
  Responses APIs, backed by in-memory storage, exposed through
  `open_ai_hosting_service_collection_extensions`.
- Add `shelf: ^1.4.0` and `shelf_router: ^1.1.0` dependencies for the
  OpenAI hosting routers.
- Fix fan-in edges losing buffered messages across checkpoint/resume: pending
  fan-in contributions are now captured in `Checkpoint.fanInState` and
  restored on resume (both the in-proc and legacy execution engines). Old
  checkpoint JSON without the field remains loadable.
- Fix fan-in edges dropping all but the last message from a source that sent
  more than once before the edge released; all buffered messages are now
  delivered, ordered by source then arrival (matches upstream
  `FanInEdgeState` semantics).
- Fix streamed responses losing `responseId`, `messageId`, `createdAt`,
  `usage`, `modelId`, `rawRepresentation`, and `additionalProperties` when
  coalesced by `ChatClientAgent` and
  `PerServiceCallChatHistoryPersistingChatClient`; all call sites now share
  one `toChatResponse()` extension (ports C# `ToChatResponse`).
- Fix `A2AAgentSession.serialize()` dropping the session `stateBag`; it now
  round-trips, and legacy payloads without it remain loadable.
- Remove the unused `StatefulEdgeRunner` interface (breaking; it had no
  implementors — fan-in state is checkpointed via `Checkpoint.fanInState`).
- Rename `agent_response_t_.dart` → `agent_response_of.dart` and
  `provider_session_state_t_state_.dart` → `provider_session_state.dart`
  (library paths only; type names unchanged).
- Simplify shell executor timeout handling with a shared
  `waitForProcessExit` helper; removes an unmanaged kill timer and ensures
  the force-kill is awaited before draining output.

## 1.2.0

- Add A2A (Agent-to-Agent) protocol support:
  - Client-side `A2AAgent`, `A2AAgentOptions`, `A2AAgentSession`, and
    `A2AContinuationToken` for consuming remote agents over the A2A protocol.
  - `a2a_client_extensions` and `a2a_agent_card_extensions` helpers.
  - Server-side hosting bridge: `A2AAgentHandler`,
    `A2ARunDecisionContext`, `A2AServerRegistrationOptions`,
    `agentRunMode`, the `a2a_server_service_collection_extensions`
    registration helpers, and a `MessageConverter`.
- Add `a2a: ^4.2.0` dependency.

## 1.1.0

- Previous release.
