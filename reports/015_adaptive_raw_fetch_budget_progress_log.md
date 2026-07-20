---
title: "Adaptive Raw-Fetch Budget Progress Log"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-07-19"
---

# Adaptive Raw-Fetch Budget Progress Log

Tracks implementation of the budget-adaptivity fixes decided in
`adr/033-make-detail-raw-fetch-budget-adaptive.md`.

## Problem

Recurring field failure: the detail-stage raw-fetch budget was not adaptive per
file. When a selected unit's chunk exceeded the fixed byte cap,
`perform-raw-fetch` dropped the whole chunk and returned an empty
`raw_context`. Agent clients then fell back to manual whole-file reads, which
cost more tokens than a correctly sized retrieval budget would have.

## Stage 1 - Adaptive Raw Fetch, Budget Feedback, Level Degradation

- Status: completed.
- Scope: three approved fixes in one stage - (1) partial slicing instead of an
  all-or-nothing chunk drop, (2) actionable feedback via
  `suggested_token_budget` and a `raise_token_budget` next step, (3) adaptive
  fetch-level degradation down the
  `whole_file -> local_neighborhood -> enclosing_unit -> target_span` ladder.
- Changed files:
  - `src/semidx/runtime/retrieval.clj` - new helpers (`raw-fetch-chunk`,
    `raw-chunks-at-level`, `raw-chunks-bytes`, `fit-raw-level`,
    `truncate-line-to-bytes`, `partial-chunk-snippet`,
    `suggested-token-budget`); `perform-raw-fetch` rewritten to measure
    `required_tokens`, degrade the level, and slice oversized chunks;
    `build-detail-response` emits `raw_snippets_truncated` /
    `raw_fetch_level_degraded` truncation flags, `suggested_token_budget` in
    the packet budget, perf `budget_summary`, and stage events,
    `raw_fetch_required_tokens` in fetch-stage counters, and a top-level
    `next_step` with `recommended_action "raise_token_budget"`.
  - `src/semidx/contracts/schemas.clj` - context-packet budget mirror allows
    optional `suggested_token_budget` (plus a whitespace-only reformat of an
    adjacent `[:options ...]` form applied by the structural editor).
  - `contracts/schemas/context-packet.schema.json` - added
    `suggested_token_budget` (integer, minimum 1).
  - `test/semidx/runtime/retrieval_test.clj` - new unit suite for partial
    slicing, level degradation, zero-budget skip, disabled escalation, and
    suggestion math.
  - `MEMORY.md` - project memory entry for the behavior change.
  - `adr/033-make-detail-raw-fetch-budget-adaptive.md` - decision record.
- Intentionally preserved behavior: when the detail reserve is 0 (tiny
  requested budgets), raw fetch stays `skipped` with an empty `raw_context`;
  `required_tokens` is still measured so the suggestion can be emitted.
- Verification:
  - REPL unit probe: budget 250 on a 300-line unit returned 1 partial snippet
    (lines 1-17, 959 bytes under the 1000-byte cap), `truncated? true`,
    warning `raw_fetch_budget_limited`, `required_tokens 4323`.
  - REPL end-to-end probe on a temp repo with an oversized Python unit:
    `token_budget 600` returned a non-empty truncated snippet, flags
    `["raw_snippets_truncated" "raw_fetch_level_degraded"]`,
    `suggested_token_budget 6183`, and the `raise_token_budget` next step; the
    retry with budget 6183 returned the full 15624-character snippet with no
    truncation flags and no further suggestion.
  - `clojure -M:test` passed (`230 tests / 1614 assertions`, includes the new
    `semidx.runtime.retrieval-test` suite and the pre-existing
    `staged-detail-fetch-enforces-reserved-budget-test`).
  - `./scripts/validate-contracts.sh` passed (`checked_json_files=61`,
    `contracts_validation=ok`).
- Skipped / limitations:
  - `./scripts/run-mvp-gates.sh` and `./scripts/run-benchmarks.sh` were not
    rerun for this change; the touched surface is covered by the full unit /
    integration suite and contract validation, and benchmark fixtures do not
    assert raw-fetch truncation shapes.
- Known blockers: none.
- Notes: work was done in parallel with the language-lane extraction stages
  (`adapters.clj` / `languages/*` were intentionally not touched); commits are
  to be staged with explicit paths, separately from the lane-extraction work.

## Review Findings

None recorded yet; no external review has been requested for this change.
