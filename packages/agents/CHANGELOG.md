# Changelog

## 3.0.0

Upstream drift sync against microsoft/agent-framework `dotnet/src` through
2026-09-04 (`2c49f50`).

- **Breaking: A2A `AgentRunMode` selects the returned artifact** (upstream
  #8032). `disallowBackground`, `allowBackgroundIfSupported` and
  `allowBackgroundWhen` are renamed `returnMessage`, `returnTask` and
  `returnTaskWhen`; `shouldRunInBackground` is now `shouldReturnTask` and
  `RunInBackgroundCallback` is `ReturnTaskCallback`. The mode is no longer
  forwarded as `AgentRunOptions.allowBackgroundResponses` and is no longer
  consulted when continuing an existing task — it decides only whether a new
  message is answered with an `AgentTask` or an `AgentMessage`. A new message
  under `returnMessage` is therefore always aggregated into one message, even
  when the response carries a continuation token.
- **Breaking: file search reports lines verbatim** (upstream #7671).
  `FileSearchMatch.line` now keeps the line's own terminator, and line
  numbers count lines terminated by `\n`, `\r\n`, or a lone `\r`, so
  numbers change on content containing a lone `\r` or a trailing newline.
  Affects `file_access_grep` and `file_memory_grep`.
- **Breaking: `AgentFileStore.searchFilesAsync` is no longer abstract.** It
  now narrows candidates through the new `findMatchingFilesAsync` hook, then
  reads and numbers them, so a store implementing only the mandatory members
  gets aligned line numbers for free. A store overriding it owns the
  numbering: `FileSearchMatch.lineNumber` must be a 1-based coordinate into
  `AgentFileStore.splitLines` of the content `readFileAsync` returns.
- Added `AgentFileStore.splitLines` and `AgentFileStore.scanContent`, the
  published split and numbering primitives; both shipped stores now scan
  through `scanContent` instead of carrying their own copy of the loop.
- Added `file_access_read_lines` (`FileAccessProvider.readLinesToolName` /
  `readLinesAsync`), which reads a 1-based inclusive line range and prefixes
  each line with its number and a tab, everything after the tab verbatim, so
  a row feeds straight back into `file_access_replace_lines`. It joins the
  read-only tool group for approval and `disableWriteTools`.
- Added `FileLineEdit.expectedLine` (wire key `expected_line`): when
  supplied, a line edit is refused unless the target line still says what the
  caller saw, which catches a stale line number or a file that changed
  between read and write.
- Added `FileEditor.sliceLines`, `trimLineTerminator` and
  `lineContentLength`, and promoted `splitLinesKeepEnds` out of private.
- Added `BackgroundAgentsProviderOptions.waitTimeout` (upstream #7911),
  five minutes by default, bounding `BackgroundAgents_WaitForFirstCompletion`.
  On expiry the tool returns control and leaves the tasks running so it can
  be called again. A non-positive timeout, or one above
  `maximumWaitTimeout`, throws a `RangeError`.
- A2A task artifacts now carry the response's additional properties as
  artifact metadata (the streaming-independent part of upstream #7998).
- Raised the `extensions` constraint to `^0.7.0`.

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
