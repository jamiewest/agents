# Changelog

## 0.7.0

- **Breaking:** `ConfiguredChatClientFactory.customClientResolver` gains an
  `AgentScope? scope` parameter, forwarded from `createChatClient`. Host
  resolvers can now key per-conversation state (for example a local model's
  KV-cache lineage) to the conversation a client serves, removing the need
  for scope-aware factory subclasses.
- Removed the empty, never-exported `src/ai_agent_provider.dart` placeholder.
- New `telemetry/` subsystem, folded in from the downstream app: `UsageStore`
  (the durable `usage_records` ledger implementing `UsageRecordSink`, now
  living beside `UsageTrackingChatClient`), `AgentRunTelemetryStore` with
  crash recovery (`recoverInterrupted`), `AgentRunScope` (an `AgentScope`
  carrying agent and run ids for usage attribution), and
  `AgentCenterOverview` time-series aggregation over the two ledgers.
- New `activity/` subsystem: `AppActivityMonitor` (app-wide idle signal;
  hosts report foreground transitions via `reportForeground(bool)` — a
  deliberate change from the app's `reportLifecycle(AppLifecycleState)` so
  the class stays free of Flutter imports) and the `ToolActivity` registry
  with `ToolActivityTrackingChatClient`.
- `a2a/` gains the host side to match its existing pairing client:
  `A2AHostService` (a `shelf`-backed HTTP server exposing local configured
  agents to paired devices, with single-use pairing tokens, SHA-256 bearer
  authorization, and per-caller session isolation) behind an io/stub
  conditional facade, plus `NetworkSharingSettings`. Adds `shelf` and
  `pool` dependencies (server platforms only at runtime; the web stub
  reports hosting unsupported).
- `web/` gains the search side folded in from the app:
  `SearchUrlWebSearchSource` (query any `q=`-style endpoint; JSON/SearXNG
  or HTML parsing with redirect unwrapping), `WebSearchSettings`
  (SecretStore-backed multi-endpoint config with categories and user-agent
  profiles), `WebSearchTraceLog` + `TracingWebPageLoader` (opt-in HTTP
  tracing), and `WebPageHtmlRenderer` (renamed from the app's
  `WebPageRenderer` to avoid colliding with this package's
  `web_page_renderer.dart` markdown helpers) with
  `HeadlessWebViewHtmlRenderer` — a reimplementation of the app's
  webview_flutter renderer on `flutter_inappwebview`, gated by a static
  `isSupported` (Android/iOS/macOS/Windows). The app no longer needs
  `webview_flutter`; one WebView stack serves both loading and rendering.
- Settings colocated with the subsystems they configure:
  `PushoverSettings` (→ `pushover/`), `EmbeddingSettings` (→ `memory/`,
  it *is* the `MemoryScorer` handed to `RecordStoreVectorStore`),
  `ThinkingSettings` (→ `configured_agents/`), and a new `user_profile/`
  capability folder (`UserProfileSettings` + `UserProfileContextProvider`).
  Persisted key literals are unchanged (including historical `agents_app.`
  prefixes) so existing installs keep their data.
- `activity/` also gains the chat terminal subsystem, reworked during the
  fold-in from an xterm-backed buffer to a terminal-widget-free design:
  `ChatTerminalSession` records a capped ring of semantic `TerminalEvent`s
  (command started / output chunk / completed / failed / cleared) with a
  sync broadcast `onEvent` stream and `events` replay, the `TerminalActivity`
  registry keys sessions per conversation (delegate scopes fold onto the
  parent), and `TerminalMirroringShellExecutor` mirrors any `ShellExecutor`
  into a session. Presentation — prompt markers, ANSI colors, CRLF, status
  lines — is the host renderer's job (the reference app binds events to an
  xterm buffer).
- New `package:agents_flutter/chat_provider.dart` entry point: the chat
  view-model contract folded in from the downstream app — `LlmProvider`,
  the UI-facing `ChatMessage`/`Attachment`/`MessageOrigin`/`ToolApproval`
  types, `LlmException`, `TokenSmoother`, `AgentLlmProvider` (bridges an
  `AIAgent` into the contract with tool-approval pause/resume, run
  telemetry, and activity reporting), and `EchoLlmProvider` (renamed from
  the app's `EchoProvider`; useful as a UI test double). It is a separate
  library, not part of the main barrel, because the UI-facing `ChatMessage`
  would collide with `package:extensions/ai.dart`'s wire-level
  `ChatMessage` in any file importing both.
- New `conversations/` subsystem: the `Conversation`/`ConversationSession`/
  `Channel` domain, `ConversationStore` + `ConversationSessionStore` +
  `ChannelStore` (RecordStore-backed, collection names unchanged from the
  app), `ConversationService`, the `ChatsQuery` filter model, the
  `ChatTitleSummarizer` background service, and an `addConversations()` /
  `addChatTitleSummarizer(residentTitleClient:)` registration pair.
- New `tasks/` subsystem: `AgentTask` (+ recurrence), `AgentTaskStore`,
  `TaskSchedulerService`, and `addTaskScheduler()`. The scheduler stays a
  plain singleton the host starts explicitly.
- `chat_history/` gains `ChatTranscriptStore`, co-located with
  `ChatMessageCodec`/`ChatMessageRecords` whose record shape it reads; a
  contract test now pins the record field literals and the write→read
  round-trip.
- `logging/` gains `PromptLog` and `PromptLoggingChatClient` (+
  `renderRequest`); `configured_agents/` gains
  `LoggingConfiguredChatClientFactory` (prompt capture, usage attribution,
  tool-activity tracking in one decorator stack) and
  `chooseLocalWarmupTarget` for pre-loading a local model at startup.
  The chat-client decorator is named `PromptLoggingChatClient` — not the
  app's original `LoggingChatClient` — to avoid colliding with
  `package:extensions/ai.dart`'s class of that name.

## 0.6.1

- `HeadlessWebViewPageLoader` accepts an optional `userAgent`, sent with
  every page load in place of the platform WebView's default. Hosts opt
  in explicitly (for example from a user-managed profile); when omitted,
  behavior is unchanged and the system default is sent.

## 0.6.0

- Query-aware ranking (Phase 3 of the web evidence plan) completes the
  four-tool web surface:
  - `open_web_page` accepts an optional `objective`; the returned
    `content` is then the blocks most relevant to that question — ranked
    by a BM25-style lexical scorer with heading-path credit, block-type
    weights (tables and definitions boosted for numeric questions), and
    a positional prior — instead of the page's lead content. A
    `Focused on:` header line and `[…]` gap markers keep the selection
    honest; an unmatched objective falls back to lead content with a
    note.
  - **Adjacency grouping:** a selected block always brings the headings
    above it and a short intro paragraph directly before it, so a bare
    `$25` table row never travels without its "Fees" heading.
  - New `find_in_page(pageId, query)` function ranks a cached page's
    blocks for a new question and returns the best matches with their
    `b<n>` ids; unmatched queries return the outline instead of guesses.
  - Repeated blocks are marked `duplicateOf` and skipped in rendering and
    ranking (`duplicateBlocks` count on page results), so syndication
    banners and print footers are never mistaken for independent
    confirmation.
  - `BlockScorer` seam (`FlutterHarnessAgentOptions.webBlockScorer`,
    `createWebSearchTools(blockScorer:)`) lets hosts substitute a
    semantic scorer later; scores stay internal and are never exposed to
    the model.

## 0.5.0

- Page sessions and the escalation loop (Phase 2 of the web evidence
  plan): opened pages are cached per tool set so agents can pull more of
  a page without reloading it.
  - `WebPageSessionStore` — a small LRU (default 8 pages, configurable
    via `WebSearchToolOptions.maxCachedPages`) created per
    `createWebSearchTools` call, so `page-N` ids are scoped to one agent
    build and never leak across conversations. Reopening a URL replaces
    its earlier entry.
  - `open_web_page` results now include a `pageId` for block-bearing
    loads, and its description teaches the loop: package → outline →
    `expand_page`.
  - New `expand_page(pageId, blockIds?, heading?)` function returns the
    full text of chosen blocks or a whole outline section, each run
    prefixed with its `Under: A > B` heading context. Expired ids get a
    "reopen the URL" result; malformed requests return the outline to
    steer the next call. Budget caps are reported, never silent.

## 0.4.0

- `open_web_page` returns structured evidence packages (Phase 1 of the web
  evidence plan, `doc/WEB_EVIDENCE_PLAN.md`). The extraction script is now
  a thin DOM walker emitting typed blocks; Dart classifies them, assigns
  heading paths, builds the page outline, and renders compact markdown:
  - `WebPageContent` gains `blocks` (`WebContentBlock` with heading paths,
    links, and table cells), `outline`, `structuredData` (JSON-LD, labeled
    by origin), `siteName`/`publishedTime`/`modifiedTime`/`author`,
    `contentMarkdown`, and `omittedBlocks`/`boilerplateBlocks` counts.
  - Tool results carry `content` markdown plus an `outline` with `b<n>`
    block ranges instead of flat `text`; the flat shape remains the
    fallback when block extraction yields nothing. Navigation, header,
    footer, and aside chrome is suppressed from the markdown and counted,
    never silently dropped; in-script caps and the character budget are
    reported through `omittedBlocks` and `truncated`.
  - `WebPageLoader`'s interface is unchanged and all new
    `WebPageContent` fields are additive with defaults.

## 0.3.1

- Focus-category search routing for the local `web_search` function:
  `FlutterHarnessAgentOptions.webSearchSourcesByCategory` (and the matching
  `createWebSearchTools` and `addFlutterHarnessContext` parameters) maps
  category labels — "finance", "technology" — to dedicated search sources.
  The labels become an enum on the function's `category` parameter so the
  model can steer a query to the source suited to its topic; they are the
  only part of the host's search configuration the model sees. Uncategorized
  calls use `webSearchSource`; with no default source, `category` is
  required.

## 0.3.0

- Add vendor-neutral local web search and direct page-opening tools for the
  Flutter harness. `open_web_page` renders JavaScript in an isolated,
  incognito headless WebView, extracts readable text and metadata, and applies
  a configurable public-network navigation policy.
- A configured local search source replaces the hosted web-search marker. A
  page loader may instead add only `open_web_page` while retaining hosted
  search. Both retain the existing per-agent web-search access gate.
- Add native headless page loading on Android, iOS, macOS, and Windows using
  `flutter_inappwebview`, with structured timeout, navigation, HTTP, loading,
  empty-content, and challenge-detection results. Flutter web reports the
  capability as unsupported.

## 0.2.1

- Pushover as a harness capability with per-agent gating:
  - `FlutterHarnessAgentOptions.pushoverClient` (plus
    `pushoverToolOptions`) — when a host attaches a configured
    `PushoverClient`, the harness adds the Pushover tools. Client-gated
    rather than flag-gated: the tools send real notifications, so they
    exist exactly when the host attached a client.
  - `AgentAccessConfig.enablePushover` — opt-in per saved agent, `false` by
    default. `ConfiguredAgentFactory` strips the client from agents that
    have an access record without the opt-in, wherever the client was
    attached; agents without an access record keep the harness default.
  - `createPushoverTools` and `PushoverToolOptions` — builds the send,
    quota, and receipt tool set from one configuration.

## 0.2.0

- Require `agents: ^1.6.0`, including the new live shell output stream and
  callback APIs and persistent-shell stderr capture.

## 0.1.0

First public release. Flutter integration layer for the
[`agents`](https://pub.dev/packages/agents) framework.

- `FlutterHarnessAgent` — a one-call `HarnessAgent` preconfigured with the
  Flutter capabilities, compaction, function invocation, and per-call chat
  history persistence. Reachable from a `ChatClient` via
  `asFlutterHarnessAgent(...)`, or through dependency injection with
  `addFlutterHarness(...)` / `useFlutterHarnessAgent(...)`.
- Device-capability context providers and tools, each registrable on a
  `ServiceCollection` or directly on `ChatClientAgentOptions`:
  - Temporal — `TemporalContextProvider` plus the `get_current_time` tool.
  - Connectivity — `ConnectivityContextProvider` (with `ConnectivityMonitor`)
    plus the `get_connectivity` tool.
  - Device and app info — `DeviceContextProvider`, `get_device_info`, and
    `get_app_info`, with `DeviceInfoHostedService` and
    `PackageInfoHostedService` for the DI path.
  - Location — `LocationContextProvider`, `get_current_location`, and
    `geocode_address`.
  - Network — `NetworkContextProvider` and `get_current_network_info`.
  - Wake lock — the `set_wake_lock` tool.
  - Pushover — `PushoverClient` plus the `send_pushover_notification`,
    `get_pushover_limits`, and `check_pushover_receipt` tools, registrable
    with `addPushover(...)`. Credentials stay out of the tool schema, so a
    model chooses what a notification says but never who receives it.
    Supports multipart image attachments, resolved from a model-supplied
    reference through a host-provided `PushoverAttachmentResolver`, and
    end-to-end encryption via `PushoverAesEncryptor`.
- Configured agents (`configured_agents/`): `ConfiguredAgentsManager`,
  `ConfiguredAgentFactory`, `AgentScope`, and persistent
  `AgentConfigurationStore` / `ModelSourceStore` for defining and switching
  agents at runtime.
- Model profiles (`configured_agents/model_profile/`): per-model chat and
  tool-call formats (Hermes, Llama 3, Mistral, LFM2), streaming tool-call
  decoding, think-tag filtering, GGUF metadata inspection, and
  `OpenAiCompatibleChatClient`.
- Chat history persistence: `FlutterChatHistoryProvider`, `ChatMessageCodec`,
  and stale tool-result redaction.
- Storage and memory built on `sembast`: `RecordStore` with in-memory and
  sembast backends, `RecordStoreAgentFileStore`, and
  `RecordStoreVectorStore` with a memory scorer.
- Downloads: `DownloadService` backed by `background_downloader`, plus a
  Hugging Face API client and model downloader.
- Logging: `AppLogStore`, an `AppLogStoreLoggerProvider`, and
  `AgentTrafficLoggingAgent` for recording agent request/response traffic.
- Chat client decorators: `UsageTrackingChatClient` and
  `TextFileInliningChatClient`.
- A2A pairing helpers under `a2a/`.
- Adaptive layout widgets under `layout/`.
