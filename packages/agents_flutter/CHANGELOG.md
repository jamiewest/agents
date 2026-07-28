# Changelog

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
