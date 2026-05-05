# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A Dart library that ports four C# namespaces from the [Microsoft Agents AI framework](https://github.com/microsoft/agent-framework/tree/main) ([docs](https://learn.microsoft.com/en-us/agent-framework/)) to idiomatic Dart.

| C# namespace | Dart folder |
|---|---|
| `Microsoft.Agents.AI.Abstractions` | `lib/src/abstractions/microsoft_agents_ai_abstractions/` |
| `Microsoft.Agents.AI` | `lib/src/ai/microsoft_agents_ai/` |
| `Microsoft.Agents.AI.Hosting` | `lib/src/hosting/microsoft_agents_ai_hosting/` |
| `Microsoft.Agents.AI.Workflows` | `lib/src/workflows/microsoft_agents_ai_workflows/` |

The partially-ported Dart files are guides. Use them alongside the canonical C# source to produce a functionally equivalent, idiomatic Dart implementation.

## Commands

```sh
dart pub get              # fetch dependencies
dart test                 # run all tests
dart test <path>          # run a single test file
dart analyze              # static analysis / linting
dart format lib/          # format code
```

## Architecture

Three layers under `lib/src/`:

**Abstractions** — core contracts that form the public API surface.  
Key types: `AIAgent` (abstract base), `AgentSession`, `AgentResponse`, `AgentRunContext`, `AgentRunOptions`, `AIContext`, `ChatHistoryProvider`, `DelegatingAIAgent`.

**AI** — concrete implementations and cross-cutting decorators.  
Key types: `AIAgentBuilder` (fluent builder), `LoggingAgent`, `OpenTelemetryAgent`.  
Sub-areas: `chat_client/`, `compaction/`, `evaluation/`, `memory/`, `harness/`, `skills/`.

**Workflows** — multi-agent orchestration engine.  
Key types: `Executor`, `Workflow`, `WorkflowContext`, `MessageRouter`, `ProtocolBuilder`, `ProtocolDescriptor`.  
Sub-areas: `checkpointing/`, `observability/`, `in_proc/`, `execution/`, `specialized/`.

**Hosting** — application lifecycle management (thin layer; delegates to `extensions` package).

## The `extensions` package

`extensions: ^0.3.21` is a Dart port of the `Microsoft.Extensions.*` stack. When C# source code uses framework types, use the corresponding `extensions` types — do not reimplement them.

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

**Preserve architecture, not syntax.** Port design and behavioral intent; produce idiomatic Dart.

- **No `IFoo`/`Foo` pairs.** Every Dart class is an implicit interface. Default to a single concrete type; introduce an explicit `abstract interface class` only when there is a genuine multi-implementation seam.
- **No runtime reflection.** Replace `Activator.CreateInstance`, assembly scanning, and attribute discovery with explicit factories, registries, and builder callbacks.
- **Collapse overloads.** C# method overloads become a single Dart method with named parameters.
- **Async mapping.** `Task<T>` → `Future<T>`; `IAsyncEnumerable<T>` → `Stream<T>`; `async/await` syntax is direct.
- **Cancellation.** Use `CancellationToken` from `extensions` `system.dart`, not a custom implementation.
- **`part` files.** Use only when multiple files need to share library-private (`_`) members as one logical library.
- **Nullability.** Keep nullable surfaces explicit; avoid `!` unless the value is guaranteed non-null.
- **LINQ.** Map to `Iterable` methods: `.Select` → `.map`, `.Where` → `.where`, `.Any` → `.any`, `.All` → `.every`.

## Code style

- `PascalCase` types, `lowerCamelCase` members/functions, `snake_case` files
- Lines ≤ 80 characters
- `final` by default; `const` for compile-time constants
- `dart:developer` `log()` instead of `print`
- `///` dartdoc comments on all public APIs
- Fakes/stubs preferred over mocks in tests; use `package:test` for unit tests
- Follow the Arrange-Act-Assert pattern in tests

## Package source policy

Prefer `dart:*` SDK libraries first, then the `extensions` package. Only add new pub.dev dependencies when documented on `flutter.dev`, `dart.dev`, `tools.dart.dev`, `google.dev`, or `genkit.dev`.
