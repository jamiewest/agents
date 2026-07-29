# Changelog

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
