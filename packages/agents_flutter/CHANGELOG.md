# Changelog

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
