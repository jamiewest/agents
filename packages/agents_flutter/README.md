# agents_flutter

Flutter device-capability providers and tools for the
[`agents`](../agents) package. Each provider feeds a device signal to an agent
through the `AIContextProvider` interface; matching tools let the agent query a
signal on demand.

## What's included

| Capability | Context provider | Tool |
|---|---|---|
| Temporal | `TemporalContextProvider` — injects the current **date** and time zone | `get_current_time` — current date and time, any IANA zone |
| Connectivity | `ConnectivityContextProvider` — injects an offline marker when the device has no network | `get_connectivity` — current connection type(s) |
| Wake lock | — | `set_wake_lock` — enable or disable automatic screen sleep |

## Registration

Via dependency injection:

```dart
final services = ServiceCollection()
  ..addTemporalContextProvider()      // detects the device time zone
  ..addConnectivityContextProvider(); // volatile — register after temporal
```

Or directly on `ChatClientAgentOptions`:

```dart
final options = ChatClientAgentOptions()
  ..addTemporalContextProvider()
  ..addConnectivityContextProvider();
```

Standalone action tools can be registered directly:

```dart
final options = ChatClientAgentOptions()
  ..chatOptions = ChatOptions(
    tools: [createWakeLockTool()],
  );
```

The wake-lock tool controls automatic screen sleep only; it does not keep the
app or CPU running in the background.

## Authoring a new device-context provider

One folder per capability, mirroring `temporal_service/` and `connectivity/`:

- `<capability>_context_provider.dart` — extends `AIContextProvider`.
- `<capability>_monitor.dart` (optional) — for volatile device state, subscribe
  to the platform's change stream once and cache the latest value so the
  provider reads a field synchronously, off the agent's hot path. See
  `ConnectivityMonitor` for the template (it implements `Disposable`).
- `<capability>_tool.dart` (optional) — an `AIFunction` for on-demand queries.
- `<capability>_service_collection_extensions.dart` — `ServiceCollection` and
  `ChatClientAgentOptions` registration helpers.

Export everything from `lib/agents_flutter.dart`.

### Two rules that keep prompt caches warm

Provider `instructions` land in the cached prompt prefix, so:

1. **Emit only what is stable.** `TemporalContextProvider` injects the date, not
   the clock time — a per-minute value would invalidate the cache every turn.
   Precise time lives in the `get_current_time` tool instead.
2. **Keep the no-signal path empty, and register volatile providers last.**
   Return an empty `AIContext()` when there is nothing to add (e.g. when
   online), and register volatile providers such as connectivity *after*
   daily-stable ones such as temporal, so a toggling marker does not shift the
   cached text above it.
