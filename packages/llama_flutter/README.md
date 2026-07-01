# llama_flutter

On-device LLM inference for **iOS** and **macOS**, backed by
[llama.cpp](https://github.com/ggml-org/llama.cpp).

- **Native bridge:** [Pigeon](https://pub.dev/packages/pigeon) — a typed
  `@HostApi` for control and an `@EventChannelApi` token stream.
- **Threading:** all native calls run from a dedicated Dart **worker isolate**
  (bound with `BackgroundIsolateBinaryMessenger`), so model loading and
  streaming never block the UI.
- **Backend:** a vendored `llama.xcframework` (Metal-enabled).

## One-time setup: build the xcframework

The xcframework is large and is **not** committed. Build it locally (requires
Xcode + CMake):

```sh
./scripts/build_llama_xcframework.sh
# Pin a specific upstream version:
LLAMA_REF=<tag-or-commit> ./scripts/build_llama_xcframework.sh
# Build every Apple platform (default is iOS + macOS only):
LLAMA_ALL_PLATFORMS=1 ./scripts/build_llama_xcframework.sh
```

This writes `darwin/Frameworks/llama.xcframework` (slices: `ios-arm64`,
`ios-arm64_x86_64-simulator`, `macos-arm64_x86_64`).

## Usage

```dart
final llama = LlamaFlutter();
final session = await llama.loadModel('/path/to/model.gguf');

await for (final token in session.generate('Hello, world!')) {
  stdout.write(token);
}

await session.dispose();
await llama.shutdown();
```

## Requirements & notes

- Deployment targets: **iOS 16.4 / macOS 13.3** (Metal build minimums).
- Models are loaded from a **runtime file path** — nothing is bundled. On
  sandboxed macOS the app needs `com.apple.security.files.user-selected.read-only`.
- The iOS **Simulator** has limited Metal support; pass `gpuLayers: 0` to
  `loadModel` to force CPU there.
- Regenerate the Pigeon bridge after editing `pigeons/messages.dart`:
  `dart run pigeon --input pigeons/messages.dart`.
