---
title: "Architecture Assessment: Open Plans And Idea Tracks"
doc_type: "architecture_assessment"
lifecycle: "active"
status: "current"
agent_action: "reference_for_context"
updated: "2026-07-19"
---

# Architecture Assessment: Open Plans And Idea Tracks

Baseline snapshot of what is genuinely open in this repository, produced by a
full read of all plan and idea documents cross-checked against the actual code,
progress logs, and live MCP responses (2026-07-19). Use this document as the
starting point for the next planning pass; update or supersede it when the
program state changes materially.

Inputs read in full: `plans/005`-`plans/009`, `plans/013`, `plans/014`,
`ideas/002`-`ideas/005`, `ideas/008`-`ideas/012`, `reports/010`,
`docs/roadmap-status.md`, plus code-level verification (namespace existence,
fixtures, live `create_index` / `resolve_context` payloads).

## 1. Genuinely Open Work

### 1.1 `plans/013_open_gaps_closure_program.md` — the only running program

Seven-stage program; current state:

- **Stage 1 (split `runtime/adapters.clj` into lane modules): in progress.**
  Shared helpers, Clojure, Java, Python, and Lua lanes are extracted
  (commits `bc9117f`, `7d3f4ae`, `06201dd`, `12c2605`, `0b4d630`). Remaining:
  the JavaScript lane and collapsing `adapters.clj` into a thin dispatch
  facade over `language_registry` + lane modules.
- **Stages 2-7: not started.**
  2. Remove the tree-sitter external-CLI runtime dependency (ADR-034 decision
     pending: embed, vendor, or formalize regex fallback as guaranteed default).
  3. Interprocedural / dataflow-sensitive resolution v1 (the major semantic
     tranche; see the architectural fork in section 4).
  4. Semantic graph query surface (bounded multi-hop traversal over
     `storage.clj`, contract-first).
  5. gRPC generated stubs (replace runtime descriptor-built messages).
  6. Online policy control-plane API (bounded, offline governance stays
     authoritative).
  7. Runtime-edge rate limiting (opt-in, default off).

### 1.2 `plans/007_semidx_extension_architecture_resolution_plan.md` — partially realized architecture

- **Delivered:** Stages 0-1 (contract baselines, workspace state, freshness
  policy, index lifecycle coordinator) — implemented via `plans/008` as
  `workspace_state.clj`, `freshness.clj`, `index_lifecycle.clj`; lifecycle
  fields are live in `create_index` responses.
- **Not started:** Stages 2-8. There is no `providers.clj`,
  `provider_selection.clj`, or `relations.clj` in `src/semidx/runtime/`.
  Open in order: minimal provider catalog + deterministic selection policy;
  discovery separation from language activation; typed relations in shadow
  mode; Markdown vertical slice; YAML vertical slice; incremental relation
  resolution; provider expansion (Kotlin, LSP, JetBrains).
- **Binding constraint already decided:** Markdown/YAML indexing must arrive
  through the provider catalog (Stage 2), never as hardcoded dispatch
  exceptions. Any "index docs now" shortcut violates this architecture plan.

## 2. Plans That Were Marked Active But Are Delivered

Verified against code and fixed in commit `74e3d4e` (frontmatter flipped to
`completed` / `historical_reference_only`):

| Plan | Delivery evidence |
|---|---|
| `plans/005` multi-clone repo identity | `repo_identity.clj`; repo-aware helpers in `storage.clj`; ADR-031/032; `repo_identity` block in live `create_index` responses |
| `plans/006` resolve_context hardening | `query_anchors.clj`; `hint_suspected_symbol_*` / `source_path_prior` policy codes observed in live responses; `fixtures/retrieval/shorthand-*.json` present |
| `plans/008` Stage 0+1 workspace freshness | `workspace_state.clj` / `freshness.clj` / `index_lifecycle.clj`; lifecycle fields in responses |
| `plans/009` HTML/CSS language lanes | `languages/html.clj` / `css.clj`; onboarding tests; languages active in the index (optional tree-sitter follow-up folds into 013 Stage 2) |
| `plans/014` capability self-description | `capabilities.clj` + MCP `capabilities` tool + `capabilities.schema.json`; `reports/010` closes with "Stage 4 and 5 are now fully green and verified" |

Residual note on `plans/006`: `fixtures/retrieval/shorthand-ambiguous-low-evidence.json`
named in the plan was not found (2 of 3 shorthand fixtures exist), and
`reports/011` records a remaining intent-only test-retrieval recall gap. The
plan is delivered; the gap is a candidate input for a future retrieval-quality
pass, not a reason to reopen the plan.

## 3. Idea Inventory — Two Tracks

### Track A: "Semantic Core" (separate system, not semidx work)

Chain: `ideas/002` (raw brainstorm) → `ideas/003` (manifesto: S-Quant, semantic
ledger, projections, arbitration) → `ideas/004` (architecture plan) →
`ideas/005` (adversarial review of 004).

The review in `ideas/005` is the governing document of this track. Its key
findings: the S-Quant is a god object and must be decomposed; the logical hash
algorithm is load-bearing and must be designed and frozen first; the Authority
Arbiter and Contract Engine are boundaries around problems that do not exist
before slice 5; slice 1 is not thin enough. Its **stop condition** gates the
whole track:

> After hash + embedding validation, evaluate whether semantic search over a
> Clojure codebase is meaningfully better than what semidx already does
> structurally. If not, the premise needs revisiting before building the
> ledger, diff, and authority layers.

No implementation should start on this track without that validation slice.

### Track B: "Agent workflow substrate" (semidx evolution)

- **`ideas/012` state invariant context — the most mature idea.** Observed
  failure case (JobApplicationTracker OAuth Stage 7), concrete packet shape
  (entity fields, writers/transitions, assertion tests, fixture helpers,
  schema hints, guardrail recommendation), acceptance criteria, and a
  non-breaking delivery path: enrich `impact_analysis` / `expand_context`
  first, no dedicated tool. Best candidate for the next new implementation
  plan.
- **`ideas/011` agent graph intelligence layer** — a menu of 11 items. Already
  delivered by other work: content-hash freshness (item 5) and
  impact-analysis-as-gate basics (item 7). Open candidates: deterministic
  `architecture_graph` export, `change_map` (snapshot_diff + impact_analysis),
  graph lint, dead-code candidates, computed `handoff_summary`, docs/ADR
  indexing (gated by 007 Stage 2 — see section 1.2).
- **`ideas/008` agent-development improvements** — subsumed: item 4 (freshness
  signal) delivered; item 1 (index docs) gated by provider catalog; items 2-3
  overlap with `ideas/011` items 11 and 7.
- **`ideas/009` progress.txt vs semidx** and **`ideas/010` graph tools
  research** — context/source-intake for `ideas/011`; no standalone action.

## 4. Architectural Fork To Resolve Before The Semantic Stage

`plans/013` Stage 3 (interprocedural dataflow extending the existing Semantic
IR) and `plans/007` Stage 4 (typed relations added additively with shadow-mode
parity, Decision 11) describe **overlapping edge models with different
migration disciplines**. Both documents are currently `active`; per repository
rules, conflicting current documents require an explicit decision, not a silent
choice by the implementing agent.

Decision needed (own ADR before 013 Stage 3 starts): do interprocedural /
dataflow edges land directly in the existing IR (013's path), or through the
typed-relation model with dual-write and golden-parity gates (007's path)?
The 007 path is stricter and protects existing graph consumers; the 013 path
is lighter but risks a later forced migration.

## 5. Recommended Order

1. ~~Hygiene commit: flip stale frontmatter on delivered plans~~ — **done**
   (`74e3d4e`).
2. Finish 013 Stage 1: JavaScript lane extraction + collapse `adapters.clj`
   into a thin facade; run the full parity gates from the plan.
3. Resolve the section-4 fork in a dedicated ADR before any 013 Stage 3 work.
4. First new plan from the idea backlog: `ideas/012` state invariant context —
   it fits the existing staged-retrieval contract and does not wait for the
   provider catalog.
5. Content update to `docs/roadmap-status.md` Current Focus (still describes
   plans 002-004 as the frontier; should point at the 013 program and this
   assessment).

## 6. Related Recent Work (context)

- Adaptive raw-fetch budget (ADR-033, `reports/015`): detail-stage raw fetch
  now degrades level and slices oversized chunks instead of returning an empty
  `raw_context`, and emits `suggested_token_budget` + `raise_token_budget`
  next-step guidance. Relevant to any future retrieval-quality work in
  Track B.
