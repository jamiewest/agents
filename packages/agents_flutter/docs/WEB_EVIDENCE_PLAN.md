# Web Evidence Pipeline Plan

Turn `open_web_page` results from flattened `innerText` into query-aware,
source-backed evidence packages, and give agents an escalation loop over
cached pages. Planned 2026-07-29; decisions below are locked with Jamie.

## Locked decisions

- **Scope: Phases 1–3** (structured extraction → page sessions + expand
  tools → query-aware ranking). Phases 4–5 are follow-on work, not v1.
- **Tool surface: 4 tools.** `web_search` and `open_web_page` (gaining an
  optional `objective` parameter) plus new `expand_page` and
  `find_in_page`. No `follow_link` / `get_raw_html` / `render_page` /
  `inspect_search_results` — they collapse into the four or cost too many
  per-turn prompt tokens (tool bloat is a known local-llama perf lever).
- **Ranking: lexical + structural only.** BM25-style term scoring,
  heading-path matches, block-type weights, adjacency grouping. A
  `BlockScorer` seam is left open; embeddings (via the app's
  `EmbeddingSettings`) and any model-assisted triage pass are explicitly
  deferred.

## Principles

- **JS thin, Dart thick.** The WebView extraction script only walks the
  DOM and emits a raw block tree; classification, ranking, rendering, and
  budgets happen in pure Dart so they are unit-testable without a WebView.
- **No fabricated scores.** Report facts (domain, dates, page kind,
  retrieval time, rank order); never invented floats like
  `"authority": 0.96`. Internal relevance scores are not exposed.
- **The model judges sufficiency.** No `missingInformation` /
  `answerability` fields from the extractor. Instead every package carries
  the full page **outline** (heading tree + block-id ranges +
  `omittedBlocks` count) so the model sees what else exists and decides
  what to expand or search next.
- **Enable synthesis, don't pre-judge it.** No conflict objects or claim
  validation in the tool; dates + provenance ids + dedup markers give the
  model what it needs.
- **Additive API only.** `WebPageLoader`'s interface is frozen (the app's
  `TracingWebPageLoader` implements it); `WebPageContent` grows new
  optional fields and keeps `text` as fallback.

## Architecture

All work in `packages/agents_flutter` (never `packages/agents`). The app
(`~/Developer/agents_app`) needs no v1 changes — richer results flow
through existing wiring, and the web-request trace inspector
(Settings › Web search) is the before/after measurement tool.

```
open_web_page(url, objective?)
  → HeadlessWebViewPageLoader
      → extraction script: raw block tree + metadata + JSON-LD (capped)
      → Dart: classify blocks, build WebPageContent (+blocks, +outline)
  → WebPageSessionStore.put(pageId, content)        [Phase 2]
  → EvidenceBuilder(objective): rank → select under budget → render
  → tool JSON: metadata, outline, evidence markdown, provenance ids
expand_page / find_in_page → WebPageSessionStore lookups  [Phase 2]
```

New types (`lib/src/web/`):

- `WebContentBlock` — id, type (`heading|paragraph|list|table|code|quote|
  definition|nav|footer|aside|form|media|other`), text, headingPath,
  sourceOrder, domPath, tableData (columns/rows) for tables, links,
  flags (boilerplate, suspectedInjection later).
- `WebPageOutline` — heading tree with block-id ranges.
- Structured-data entries (JSON-LD / OpenGraph / microdata) with format
  labels.
- `WebPageSessionStore` — per-tool-set LRU (default 8 pages, text-capped),
  created in `createWebSearchTools`, shared by the two new tools; expired
  ids return a "page expired — reopen the URL" result. Same
  `disableWebSearch` gate covers all four tools.
- `EvidenceBuilder` + `BlockScorer` seam — pure Dart.
- `WebSearchToolOptions` additions: `maxEvidenceCharacters`,
  `maxBlocksPerResponse`, `maxCachedPages`, in-script block/size caps.

Extraction script contract: emits JSON `{meta, blocks[], structured[],
truncated}`; capped in-script (~500 blocks / bounded chars per block)
because `evaluateJavascript` return size is a real platform limit; caps
surface as `omittedBlocks`, never silently.

## Phases

### Phase 1 — structured extraction (highest leverage) — DONE 2026-07-29

- Rewrite `_extractionScript` as a DOM walker (headings h1–h6 with
  hierarchy, paragraphs, lists, tables with cells, pre/code, blockquote,
  links with hrefs, alt text; skip hidden elements; tag nav/footer/aside/
  banner candidates by landmark roles and tag names).
- JSON-LD (`script[type="application/ld+json"]`), OpenGraph/meta, and
  canonical extraction in the same pass.
- Dart-side: block model, boilerplate classification, heading-path
  assignment, markdown rendering (structure like the proposal's example:
  title, source, dates, content-type header, then sections), outline.
- `WebPageContent` gains `blocks`, `outline`, `structuredData`; `toJson`
  emits rendered markdown + outline instead of flat `text` (kept as
  fallback when block extraction fails or on unsupported platforms).
- Tests: pure-Dart unit tests on fixture block JSON for
  classification/rendering; extend the opt-in native fixture
  (`integration_test/headless_web_view_page_loader_test.dart`).

### Phase 2 — page sessions + escalation — DONE 2026-07-29

- `WebPageSessionStore` LRU; stable ids `page-N` / `block-N` per session.
- `expand_page(pageId, blockIds?, headingPath?)` — full-length cached
  blocks for a section or id list.
- `find_in_page(pageId, query)` — re-rank cached blocks for a new
  question (uses Phase 3 scorer; ships in whichever phase lands second).
- Tool docs/results teach the loop: package → outline → expand.

### Phase 3 — query-aware ranking — DONE 2026-07-29

- `objective` parameter on `open_web_page` (optional; without it, return
  the lead content + outline as today's ordering does).
- Scorer: BM25-style lexical over block text, heading-path term matches,
  block-type weights (tables/definitions boosted for entity+number
  queries), positional prior, boilerplate suppression.
- **Adjacency grouping:** heading + intro paragraph + table travel as one
  evidence unit; never rank a bare "$25" row apart from its "Fees"
  heading.
- Selection under `maxEvidenceCharacters`; block-level dedup hashing
  within a page (repeat blocks marked `duplicateOf`).

### Phase 4 — hardening (follow-on, not v1)

- Injection flagging: lexical detector → `suspectedInjection` flag,
  excluded from ranking by default, labeled when explicitly expanded
  (label, don't strip).
- Page-kind classification (article/docs/forum/product/government/
  login/error) → extraction presets per kind.
- Cross-page dedup via the session store.
- Table dual form (structured + one-line natural language).

### Phase 5 — optional/later

- Embedding `BlockScorer` plugged from the app's `EmbeddingSettings`.
- Idle-gated model-assisted triage pass (contends with the resident
  llama's pool lease — measure first).
- Per-kind deep strategies (forum reply threading, legal numbering).

## Explicitly rejected from the source proposal

- Fabricated authority/freshness/relevance floats — ungrounded precision.
- Extractor-produced `missingInformation`/`answerability` — model
  judgment; outline replaces it.
- Conflict objects with `likelyResolution`, claim-to-evidence validation
  — answer-side reasoning, not tool output.
- Entity/relationship extraction — heavy NLP, marginal over structure.
- ~10-tool surface, `follow_link`, `render_page`, raw-HTML tool — token
  cost; collapsed into 4 tools with expand modes.

## Measurement

Use the Settings › Web search trace inspector to compare package size and
content per request before/after each phase (the trace already captures
every tool call's response body). Success: smaller median `open_web_page`
responses that still let the model answer fixture questions, plus
observed `expand_page` usage instead of full-page dumps.
