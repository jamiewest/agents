# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repository is

A Dart **workspace monorepo** (see root `pubspec.yaml`) holding the core
framework packages under `packages/`:

| Package | What it is |
|---|---|
| `packages/agents` | Dart port of the C# [Microsoft Agents AI framework](https://github.com/microsoft/agent-framework). **Read the warning below before editing.** |
| `packages/agents_flutter` | Flutter integration layer for `agents` (configured agents, chat history codecs, providers). |

The llama inference packages and the app were split into sibling repositories
in July 2026 and consume this repo via commit-pinned Git dependencies:

- [`jamiewest/agents_llama`](https://github.com/jamiewest/agents_llama) —
  `agents_llama` + `llama_flutter` (local checkout: `~/Developer/agents_llama`)
- [`jamiewest/agents_app`](https://github.com/jamiewest/agents_app) — the
  Flutter app at the repo root (local checkout: `~/Developer/agents_app`)

Directories for those packages may still linger under `packages/` here; they
are gitignored build-artifact remnants, not source. Never edit them — the real
code lives in the sibling checkouts. For coordinated development, the
downstream repos use `pubspec_overrides.yaml` (see each repo's
`pubspec_overrides.yaml.example`) pointing at sibling checkouts.

There is no repo-root `lib/`; if guidance references one, it is stale.

## ⚠️ packages/agents is upstream-mirrored

`packages/agents` ports the upstream C# framework: its shapes and design
decisions mirror `dotnet/src/*` upstream, with deliberate idiomatic-Dart
deviations recorded in `packages/agents/PORTING.md`. A broken intermediate
state there is usually Jamie's mid-port work-in-progress — check the upstream
C# source and ask about intent before restructuring or "fixing" it. Porting
rules live in `packages/agents/CLAUDE.md`; use the `/drift` skill to audit
upstream sync.

## Commands

Run per package, from that package's directory:

```sh
cd packages/agents            # or packages/agents_flutter
dart pub get                  # fetch dependencies
dart test                     # run all tests
dart test test/<file>_test.dart   # run a single test file
dart analyze                  # static analysis / linting
dart format lib test          # format code
```

`packages/agents_flutter` is a Flutter package — use `flutter test` /
`flutter analyze` there. Running `dart test` on a Flutter package fails with a
kernel-compiler crash (`InvalidType` in a `NativeCallable` cast); that error
means "wrong test runner", not a broken package.

**Ripple rule:** analyzing `packages/agents` alone does not catch subclass
breaks in dependents. After changing any base contract in `agents`, also run
analysis in `agents_flutter`, and ideally in the external `agents_llama` and
`agents_app` checkouts — they pin this repo by commit, so breaks surface when
they bump their ref (see `packages/agents/PORTING.md`).

## Other repo docs

- `packages.md` — approved pub.dev packages and when to prefer them over
  custom code. Check it before adding any dependency.
- `rules.md` — Flutter/Dart style rules (mainly for the app packages).
- `packages/agents/PORTING.md` — intentional divergences from upstream C#;
  never re-flag entries there as drift or bugs.
