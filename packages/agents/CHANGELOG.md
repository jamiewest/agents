# Changelog

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
