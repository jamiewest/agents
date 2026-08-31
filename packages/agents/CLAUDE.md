# CLAUDE.md — packages/agents

A Dart port of the C# [Microsoft Agents AI framework]
(https://github.com/microsoft/agent-framework)
([docs](https://learn.microsoft.com/en-us/agent-framework/)). Architecture
mirrors upstream `dotnet/src/*`; the Dart code is idiomatic, not a
line-by-line translation.

**Before flagging drift, bugs, or missing APIs, read [PORTING.md](PORTING.md)**
— it holds the folder → upstream namespace map, the ledger of intentional
divergences (do not re-flag them), and recurring porting gotchas. Use the
`/drift` skill to audit upstream sync.

**Design decisions here are Jamie's.** A broken intermediate state is usually
mid-port work-in-progress, not a bug to fix. Check the corresponding upstream
C# source and ask about intent before restructuring anything.

## Commands

Run from this directory (`packages/agents/`):

```sh
dart pub get              # fetch dependencies
dart test                 # run all tests
dart test test/<file>_test.dart   # run a single test file
dart analyze              # static analysis / linting
dart format lib test      # format code
```

After changing any base contract (abstract class, public method signature),
also run `dart analyze` in `packages/agents_flutter` and
`packages/agents_app` — analysis here does not catch subclass breaks in
dependent packages (see PORTING.md "Porting gotchas").

## Layout

Public entry point is `lib/agents.dart`; implementation lives under
`lib/src/`. The full folder → upstream namespace table is in PORTING.md.
The core areas:

- `abstractions/` — core contracts (`AIAgent`, `AgentSession`,
  `AgentResponse`, `AgentRunOptions`, `AIContext`, `ChatHistoryProvider`,
  `DelegatingAIAgent`).
- `ai/` — concrete implementations and decorators (`AIAgentBuilder`,
  `LoggingAgent`, `OpenTelemetryAgent`); sub-areas `chat_client/`,
  `compaction/`, `evaluation/`, `memory/`, `harness/`, `skills/`,
  `open_ai/`.
- `workflows/` — multi-agent orchestration (`Executor`, `Workflow`,
  `WorkflowContext`, `MessageRouter`); sub-areas `checkpointing/`,
  `observability/`, `in_proc/`, `execution/`, `specialized/`.
- `hosting/` — lifecycle/session-store integration (+ `a2a/`, `open_ai/`,
  `local/`).
- `a2a/`, `anthropic/`, `gemini/`, `harness/`, `mcp/`, `tools/shell/` —
  see PORTING.md.

Tests are flat in `test/`, named `<feature>_test.dart`.

## The `extensions` package

`extensions: ^0.6.0` is a Dart port of the `Microsoft.Extensions.*` stack.
When C# source uses framework types, use the corresponding `extensions`
types — do not reimplement them.

| C# type | `extensions` module | Dart type |
|---|---|---|
| `IServiceCollection` / `ServiceCollection` | `dependency_injection.dart` | `ServiceCollection` |
| `IServiceProvider` | `dependency_injection.dart` | `ServiceProvider` |
| `HostApplicationBuilder` | `hosting.dart` | `HostApplicationBuilder` |
| `IHost` / hosted services | `hosting.dart` | `Host`, `BackgroundService` |
| `ILogger<T>` / `ILoggerFactory` | `logging.dart` | `Logger`, `LoggerFactory` |
| `IOptions<T>` / `IOptionsMonitor<T>` | `options.dart` | `Options`, `OptionsMonitor` |
| `IConfiguration` | `configuration.dart` | `ConfigurationManager` |
| `IMemoryCache` | `caching.dart` | `MemoryCache` |
| `CancellationToken` / `CancellationTokenSource` | `system.dart` | `CancellationToken`, `CancellationTokenSource` |
| `IDisposable` / `IAsyncDisposable` | `system.dart` | `Disposable`, `AsyncDisposable` |
| `IChangeToken` | `primitives.dart` | `ChangeToken` |

## C# to Dart porting rules

**Preserve architecture, not syntax.** Port design and behavioral intent;
produce idiomatic Dart.

- **No `IFoo`/`Foo` pairs.** Every Dart class is an implicit interface.
  Default to a single concrete type; introduce an explicit
  `abstract interface class` only for a genuine multi-implementation seam.
- **No runtime reflection.** Replace `Activator.CreateInstance`, assembly
  scanning, and attribute discovery with explicit factories, registries,
  converters, and builder callbacks (see PORTING.md for existing idioms:
  `ChatMessageJsonConverter`, `stateRehydrator`, `*_json_utilities.dart`).
- **Collapse overloads.** C# method overloads become a single Dart method
  with named parameters.
- **Async mapping.** `Task<T>` → `Future<T>`; `IAsyncEnumerable<T>` →
  `Stream<T>`; `async`/`await` is direct.
- **Cancellation.** Use `CancellationToken` from `extensions` `system.dart`.
- **`part` files.** Only when multiple files must share library-private
  (`_`) members as one logical library.
- **Nullability.** Keep nullable surfaces explicit; avoid `!` unless the
  value is guaranteed non-null.
- **LINQ.** `.Select` → `.map`, `.Where` → `.where`, `.Any` → `.any`,
  `.All` → `.every`.

## Code style

- `PascalCase` types, `lowerCamelCase` members/functions, `snake_case` files
- Lines ≤ 80 characters
- `final` by default; `const` for compile-time constants
- `dart:developer` `log()` instead of `print`
- `///` dartdoc comments on all public APIs
- Fakes/stubs preferred over mocks; `package:test` for unit tests
- Arrange-Act-Assert pattern in tests

## Package source policy

Prefer `dart:*` SDK libraries first, then the `extensions` package, then the
approved packages documented in the repo-root [packages.md](../../packages.md).
Only add other pub.dev dependencies when documented on `flutter.dev`,
`dart.dev`, `tools.dart.dev`, `google.dev`, or `genkit.dev`.
