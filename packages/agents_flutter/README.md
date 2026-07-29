# agents_flutter

Flutter integration layer for the
[`agents`](https://pub.dev/packages/agents) package: a preconfigured harness
agent, device-capability context providers and tools, chat history persistence,
and configurable model profiles.

Each device-capability provider feeds a signal to an agent through the
`AIContextProvider` interface; matching tools let the agent query a signal on
demand.

## Installation

```sh
flutter pub add agents_flutter
```

A runnable single-screen app lives in
[`example/`](https://github.com/jamiewest/agents/tree/main/packages/agents_flutter/example).

### Platform setup

This package pulls in plugins that need platform permission declarations. Only
the capabilities you actually enable require them, but iOS builds are rejected
at review if a linked framework's usage description is missing — so declare the
ones your app uses:

| Capability | iOS `Info.plist` | Android `AndroidManifest.xml` |
|---|---|---|
| Location (`enableLocation`) | `NSLocationWhenInUseUsageDescription` | `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` |
| Network info (`enableNetworkInfo`) | `NSLocationWhenInUseUsageDescription` (iOS gates SSID behind location) | `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE` |
| Camera / image capture | `NSCameraUsageDescription` | `CAMERA` |
| Photo picker | `NSPhotoLibraryUsageDescription` | — |
| Audio capture | `NSMicrophoneUsageDescription` | `RECORD_AUDIO` |
| Downloads, model fetching | — | `INTERNET` |
| Headless web browsing | — | `INTERNET` |

On macOS, `flutter_secure_storage` also needs the Keychain Sharing capability
in both the debug and release entitlements files. See each plugin's own README
for the authoritative list.

Headless web browsing supports Android, iOS, macOS, and Windows. Sandboxed
macOS apps must enable the `com.apple.security.network.client` entitlement in
their debug/profile and release entitlements. Windows hosts need the WebView2
runtime and NuGet CLI required by
[`flutter_inappwebview`](https://pub.dev/packages/flutter_inappwebview). Flutter
web is intentionally unsupported because a cross-origin iframe cannot provide
equivalent DOM extraction. See the plugin's
[headless WebView documentation](https://inappwebview.dev/docs/webview/headless-in-app-webview/)
for its native setup details.

## What's included

| Capability | Context provider | Tool |
|---|---|---|
| Temporal | `TemporalContextProvider` — injects the current **date** and time zone | `get_current_time` — current date and time, any IANA zone |
| Connectivity | `ConnectivityContextProvider` — injects an offline marker when the device has no network | `get_connectivity` — current connection type(s) |
| Wake lock | — | `set_wake_lock` — enable or disable automatic screen sleep |

Also available: `get_app_info`, the `DeviceContextProvider` + `get_device_info`,
the `LocationContextProvider` + `get_current_location`/`geocode_address`, and the
`NetworkContextProvider` + `get_current_network_info`.

## Flutter harness agent

`FlutterHarnessAgent` is the one-call way to get a full
[`HarnessAgent`](https://pub.dev/packages/agents) — compaction, function
invocation, per-call chat history persistence — preconfigured with the Flutter
capabilities. Safe-core
capabilities (temporal, connectivity, app info, device info) are on by default;
location, detailed network info, and the wake-lock tool are opt-in.

Directly from a `ChatClient`:

```dart
final agent = chatClient.asFlutterHarnessAgent(
  1050000, // model context-window tokens
  128000,  // model per-response output tokens
  options: FlutterHarnessAgentOptions()..enableLocation = true,
);
```

Or via dependency injection, registering the device/app info background services
and an `AIAgent` resolvable from the provider:

```dart
services.addFlutter((flutter) => flutter.useFlutterHarnessAgent(
  configure: (options) => options.enableNetworkInfo = true,
));
```

`ServiceCollection.addFlutterHarness(...)` and
`HostApplicationBuilder.addFlutterHarness(...)` are the same registration without
the `FlutterBuilder` wrapper. The direct path populates the device and app info
caches in the background; the DI path uses `DeviceInfoHostedService` and
`PackageInfoHostedService` instead.

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

## Local web search and page opening

The Flutter harness normally exposes the model provider's hosted web-search
marker. Supplying a local search source replaces that marker with two ordinary
function tools:

- `web_search` asks the host-provided backend for titles, URLs, and snippets.
- `open_web_page` accepts a direct URL and extracts readable text in a fresh,
  incognito, headless system WebView.

The library never embeds a search API key. Implement `WebSearchSource` in the
host application and keep its credentials outside the model-visible tool
arguments:

```dart
final agent = chatClient.asFlutterHarnessAgent(
  1050000,
  128000,
  options: FlutterHarnessAgentOptions(
    webSearchSource: MySearchSource(apiKey: searchApiKey),
  ),
);
```

Hosts with topic-specific backends can add focus categories. The category
labels become an enum on `web_search`'s `category` parameter so the model
steers each query to the source suited to its topic — a history question
never hits the finance endpoint. The labels are the only part of the search
configuration the model sees; calls without a category use
`webSearchSource`, and when that is omitted a category is required:

```dart
final options = FlutterHarnessAgentOptions(
  webSearchSource: MySearchSource(apiKey: searchApiKey),
  webSearchSourcesByCategory: {
    'finance': MyFinanceSearchSource(),
    'technology': MyTechnologySearchSource(),
  },
);
```

Configure only a page loader to add direct page opening without replacing the
harness's hosted search marker:

```dart
final options = FlutterHarnessAgentOptions(
  webPageLoader: HeadlessWebViewPageLoader(),
);
```

By default, `open_web_page` accepts public HTTP and HTTPS URLs and rejects
embedded credentials, local names, and private, loopback, link-local,
multicast, or otherwise non-public resolved addresses. A host can inject a
`WebNavigationPolicy` to permit a different scope, but doing so can expose
device or LAN services to model-directed requests. An injected
`WebPageLoader` owns its own navigation and redirect safeguards;
`webNavigationPolicy` configures the built-in headless loader.

Each call creates and disposes its own incognito WebView. The implementation
does not clear or reuse the plugin's shared cookie store, override the system
user agent, simulate clicks or scrolling, solve CAPTCHAs, or attempt to bypass
site protections. Sites may still identify the client as an embedded WebView.

The native smoke fixture is opt-in and is not part of Linux CI. Because this
package does not carry generated native runner projects, run the fixture from
a Flutter host application that depends on this checkout (and has the required
network permissions):

```sh
flutter test integration_test/headless_web_view_page_loader_test.dart -d macos
```

## Authoring a new device-context provider

One folder per capability, mirroring `temporal/` and `connectivity/`:

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
