---
description: Check for drift between the upstream C# Microsoft Agents AI framework and this Dart port. Use when asked to check drift, port sync, upstream changes, or implementation gaps.
argument-hint: [sync | full | abstractions|ai|hosting|workflows|a2a|anthropic|harness|mcp|tools] (default: incremental review since last sync)
allowed-tools: [Read, Bash, WebFetch, Glob, Grep, Edit, Write]
---

# Port Drift Check

You are auditing drift between the upstream C# Microsoft Agents AI framework
(https://github.com/microsoft/agent-framework) and the Dart port at
`packages/agents/`. All paths below are relative to the repository root.

## Modes

| Invocation | What it does |
|---|---|
| `/drift` | **Incremental review** — list and classify upstream `dotnet/src` commits since the last sync pin. Report only; no code changes. |
| `/drift sync` | Incremental review, then **port the applicable changes**, update the pin, and prepare a branch + PR. |
| `/drift full` | Exhaustive structural audit (every namespace) — the pre-incremental behavior. |
| `/drift <namespace>` | Exhaustive audit scoped to one namespace from the map below. |

## Step 0 — Read the divergence ledger (REQUIRED FIRST, all modes)

Read `packages/agents/PORTING.md` in full before anything else. It contains:

- the **upstream sync pin** (`upstream-sync: <sha> <date>` line) — the newest
  upstream `dotnet/src` commit already reviewed,
- the folder → upstream namespace map (authoritative; use it, not guesses),
- **intentional divergences** and **verified-faithful** entries — these must
  NOT appear as findings in your report,
- the list of upstream projects that are out of scope,
- Dart-original folders that have no upstream counterpart.

Keep a count of findings you suppressed because the ledger covers them; the
report must state that count so suppression is auditable.

## Namespace scope

| Argument     | C# path prefix (`dotnet/src/`)             | Dart folder (`packages/agents/lib/src/`) |
|--------------|--------------------------------------------|------------------------------------------|
| abstractions | Microsoft.Agents.AI.Abstractions           | abstractions |
| ai           | Microsoft.Agents.AI (exact) + .OpenAI      | ai (incl. ai/open_ai) |
| hosting      | Microsoft.Agents.AI.Hosting (+ .A2A/.OpenAI) | hosting (incl. hosting/a2a, hosting/open_ai) |
| workflows    | Microsoft.Agents.AI.Workflows              | workflows |
| a2a          | Microsoft.Agents.AI.A2A                    | a2a |
| anthropic    | Microsoft.Agents.AI.Anthropic              | anthropic |
| harness      | Microsoft.Agents.AI.Harness                | harness |
| mcp          | Microsoft.Agents.AI.Mcp                    | mcp |
| tools        | Microsoft.Agents.AI.Tools.Shell            | tools/shell |

Do NOT scan `gemini/` or `hosting/local/` against upstream — they are
Dart-original (see PORTING.md). Upstream projects listed as "not ported" in
PORTING.md are out of scope; do not report their types as missing — but DO
list a **new** upstream project (one in neither the map nor the not-ported
list) as "needs triage" so Jamie can decide.

---

# Incremental mode (`/drift`, `/drift sync`)

## Step I1 — Collect upstream commits since the pin

Read the pin SHA from PORTING.md, then page through:

```bash
curl -s "https://api.github.com/repos/microsoft/agent-framework/commits?path=dotnet/src&per_page=100&page=1"
```

Collect commits (sha, date, title, PR number from the title) from newest until
you reach the pin SHA. If the pin does not appear within 3 pages, stop and say
the backlog is 300+ commits — recommend `/drift full` instead. If there are
zero new commits, report "in sync as of <pin date>" and stop.

## Step I2 — Classify each commit

For each new commit, fetch its file list:

```bash
curl -s "https://api.github.com/repos/microsoft/agent-framework/commits/<sha>"
```

(the response includes per-file paths and patches). Classify:

- **Out of scope** — every touched `dotnet/src` file belongs to a not-ported
  project, or the change is tests/csproj/build-only. Record one line, move on.
- **Applicable** — touches an in-scope project's non-test source. Read the
  patch (fetch full files via
  `https://raw.githubusercontent.com/microsoft/agent-framework/main/<path>`
  when the patch lacks context) and the corresponding Dart code, then decide:
  - **port** — behavior/API change the Dart port should mirror,
  - **already covered** — the port already behaves this way (say why),
  - **skip (ledger)** — covered by a PORTING.md entry (count as suppressed),
  - **skip (propose)** — you judge it not applicable (e.g. .NET-only
    machinery); needs a new PORTING.md entry recording that decision.

## Step I2.5 — Extensions dependency edge

The port's `package:extensions` (jamiewest/extensions, sibling checkout
`~/Developer/extensions`) plays the role upstream's Microsoft.Extensions.AI
NuGet packages play for agent-framework. Drift can enter through that edge
even when no `dotnet/src` commit looks applicable, so every incremental run
also checks:

1. **Upstream MEAI version bump** — compare the `Microsoft.Extensions.AI*`
   versions in `dotnet/Directory.Packages.props` at the pin vs `main`:

   ```bash
   curl -s "https://raw.githubusercontent.com/microsoft/agent-framework/<pin sha>/dotnet/Directory.Packages.props" | grep "Microsoft.Extensions.AI"
   curl -s "https://raw.githubusercontent.com/microsoft/agent-framework/main/dotnet/Directory.Packages.props" | grep "Microsoft.Extensions.AI"
   ```

   A bump means upstream may now rely on newer MEAI APIs. Flag it in the
   report as **coordinate with extensions**: the extensions repo's own
   `/drift` must cover that MEAI window before (or alongside) porting the
   agent-framework changes that use it.

2. **Published-version lag** — compare the `extensions` (and, in
   `agents_flutter`, `extensions_flutter`) constraint in the pubspecs against
   the latest pub.dev release (`https://pub.dev/api/packages/extensions`).
   Report a lag; bumping is a sync-mode action (update the constraint, run
   analyze + tests, adapt call sites).

3. **Blocked ports** — in sync mode, when a "port" item needs an API that
   `package:extensions` does not expose yet, do NOT hack a local stand-in
   into this repo (the existing self-contained deviations in PORTING.md were
   deliberate, decided cases). Record the item as **blocked on extensions**
   in the report and PR body, with the exact missing API, so it can be filed
   against jamiewest/extensions; port it here only after extensions ships it,
   or after Jamie approves a recorded deviation.

## Step I3 — Report (both incremental modes)

Produce a table: upstream PR#, date, one-line summary, classification, and
for "port" items a one-line sketch of the Dart change. Then totals and the
suppressed count. In plain `/drift` mode, stop here — do not edit code.

## Step I4 — Sync (only `/drift sync`)

1. Work on a branch (`drift/sync-<YYYY-MM-DD>`), never directly on `main`
   (in an environment that already put you on a work branch, use that).
2. Port each "port" item faithfully — mirror upstream shapes per
   `packages/agents/CLAUDE.md`; when Dart idiom forces a deviation, record it
   in PORTING.md with a date. Add or extend tests mirroring upstream's where
   they exist.
3. Append PORTING.md entries for every "skip (propose)" decision, and add new
   upstream projects to the not-ported list marked "(pending triage)".
4. Advance the `upstream-sync:` pin to the newest commit reviewed — even if
   everything was skipped, so the next run starts from here.
5. Verify:
   ```bash
   cd packages/agents && dart analyze && dart test
   cd ../agents_flutter && flutter analyze && flutter test
   ```
6. Ripple: base-contract changes also need `flutter analyze` in the sibling
   checkouts `~/Developer/agents_llama` and `~/Developer/agents_app` when they
   are available (they pin this repo by commit). If they are not available
   (CI/cloud), say so in the PR body so Jamie checks on the next ref bump.
7. Commit with a body itemizing each ported upstream PR# and each recorded
   skip (match the style of commit `d191144`), push the branch, and open a PR
   with `gh pr create`. Do not merge it.

---

# Full audit mode (`/drift full`, `/drift <namespace>`)

## Step 1 — Discover C# source structure

Fetch the repo tree from the GitHub API:

  https://api.github.com/repos/microsoft/agent-framework/git/trees/main?recursive=1

If the response says `"truncated": true`, fall back to per-project trees.
Filter for `.cs` files under `dotnet/src/<project>` for each project in
scope. Exclude:
- test files (`*Test*.cs`, `*.Tests.*`)
- generated files (`*.g.cs`, `*.Designer.cs`)
- `obj/` and `bin/` directories

Collect the path and inferred public type name (filename without `.cs`).

## Step 2 — Map to Dart files and find missing types

For each C# public type found:
1. Convert PascalCase to snake_case filename — e.g. `AIAgent` →
   `ai_agent.dart`, `ChatClientAgent` → `chat_client_agent.dart`. Rules:
   `AI` → `ai`; acronyms (all-caps runs) become fully lowercase.
2. Check existence (search the whole package — small types are often
   co-located in a sibling file rather than one-file-per-type):

   ```bash
   find packages/agents/lib/src -name "<snake_case>.dart"
   # if no file, check for the type name inside existing files:
   grep -rln "class <TypeName>\b\|enum <TypeName>\b" packages/agents/lib/src
   ```
3. Record types with no match as **Not Yet Ported** — unless PORTING.md lists
   them as intentional skips (then count as suppressed).

## Step 3 — Check API surface gaps (sample-based)

For up to 10 C# types that DO have a Dart counterpart (prioritise the
abstractions layer), fetch the raw C# source via:

  https://raw.githubusercontent.com/microsoft/agent-framework/main/<path>

Extract public method and property names. Read the Dart file. Flag C# public
members that appear entirely absent from Dart. Do not flag:
- C# overloads collapsed into one Dart method with named parameters,
- the `*Async` suffix, which Dart drops (`RunAsync` → `run`,
  `SerializeSessionAsync` → `serializeSession`),
- C# `IFoo` interfaces merged into the concrete `Foo` type — check the
  I-stripped name before reporting,
- internal C# types ported as private Dart types (`_Foo`) co-located in a
  sibling file,
- renames following Dart conventions (e.g. `Continue` → `proceed`),
- anything covered by PORTING.md (count as suppressed).

## Step 4 — Implementation debt scan

```bash
grep -rn "TODO\|FIXME\|HACK\|throw UnimplementedError\|throw UnsupportedError" packages/agents/lib/src --include="*.dart"
```

Group by file. Note: `json_stubs.dart` property-name converters throw
`UnimplementedError` intentionally — mention but do not count as debt.

## Step 5 — Static analysis

```bash
cd packages/agents && dart analyze
```

Show all errors and warnings. Note the total count.

## Step 6 — Test gap check

Tests live flat in `packages/agents/test/`, named `<feature>_test.dart`.

```bash
find packages/agents/lib/src -name "*.dart" ! -name "*.g.dart" | while read f; do
  base=$(basename "$f" .dart)
  test_file=$(find packages/agents/test -name "${base}_test.dart" 2>/dev/null | head -1)
  [ -z "$test_file" ] && echo "NO_TEST: $f"
done
```

List files with no corresponding `*_test.dart`. Exclude pure re-export or
barrel files (heuristic: fewer than 20 lines). Note that coverage is grouped —
many types are covered by a feature-level test file (e.g.
`workflow_magentic_test.dart`), so treat this as a signal, not a verdict.

## Step 7 — Conformance spot-check

```bash
# IFoo-style names (prohibited — every Dart class is an implicit interface)
grep -rn "abstract interface class I[A-Z]" packages/agents/lib/src --include="*.dart"

# print() usage (use dart:developer log() instead)
grep -rn "^\s*print(" packages/agents/lib/src --include="*.dart"

# Lines > 80 characters (sample of up to 20)
find packages/agents/lib/src -name "*.dart" -exec awk 'length > 80 {print FILENAME ":" FNR}' {} + | head -20
```

## Step 8 — Ripple check (only if fixes are proposed)

If any recommended fix changes a base contract in `packages/agents`
(abstract class, public method signature, constructor shape), state that the
fix must be verified with:

```bash
cd packages/agents_flutter && flutter analyze
cd ~/Developer/agents_llama && flutter analyze   # sibling checkout, if present
cd ~/Developer/agents_app && flutter analyze     # sibling checkout, if present
```

`dart analyze` on `packages/agents` alone does not catch subclass breaks in
dependent packages. `agents_llama` and `agents_app` live in sibling repos
that pin this one by commit — if their checkouts are unavailable, note the
unverified ripple in the report/PR instead of silently skipping it.

## Full-audit report

Produce a report with the sections below. Be concise — list findings, do not
explain every item.

### Upstream Drift
- **Not yet ported** — C# type name + C# file path
- **API surface gaps** — per type, C# members absent from Dart
- **Suppressed intentional divergences: N** (per PORTING.md — list the ledger
  entry names, not the details)

### Implementation Debt
- Grouped by file: stub/TODO lines with line numbers
- Total count

### Static Analysis
- `dart analyze` output (errors first, then warnings)

### Test Gaps
- Files without tests (skip barrel/re-export files)
- Coverage ratio: X / Y source files have a test file

### Conformance
- Naming violations (`IFoo`-style names)
- `print()` usage
- Line-length violations (sample)

### Summary
- **Severity:** Low / Medium / High (your overall judgment)
- **Top 3 actions** to reduce drift, most impactful first

---

## Maintenance (all modes)

If the run concludes that a difference is deliberate (user confirms, or a
sync run records a skip), append it to `packages/agents/PORTING.md` with a
date — do not record it only in session memory. If PORTING.md's namespace map
disagrees with what you find upstream, flag that in the report too. A full
audit that ends in a clean sync may also advance the `upstream-sync:` pin.
