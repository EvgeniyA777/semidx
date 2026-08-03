---
title: "Retrieval Value Benchmark Harness Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-02"
---

# Progress Log: Retrieval Value Benchmark Harness

Companion log for
[`plans/020_retrieval_value_benchmark_harness_plan.md`](../plans/020_retrieval_value_benchmark_harness_plan.md).

## Stage Status

| Stage | Status |
| --- | --- |
| 0 — Pre-register metric, pilot-then-lock threshold | provisional threshold recorded in `SPEC.md` §5.1; pilot pending |
| 1 — Fidelity fix (`returned_tokens`) | completed |
| 2 — Task suite + three-arm harness | not started |
| 3 — Aggregator command | not started |
| 4 — First real-repo run + evidence write-back | not started |

## Stage 1 — `returned_tokens` fidelity fix (completed)

### Finding (verified in REPL)

`semidx.core/resolve-context` recorded the selection-stage event payload with
`:returned_tokens (get-in result [:budget_summary :estimated_tokens])` — it
duplicated the estimate under a name that implies a measured return, while
`expand-context` records the real measured `[:budget_summary :returned_tokens]`.

Runtime inspection confirmed the selection-stage `result` (and its metadata)
exposes no separately measured returned figure: `:budget_summary` carries only
`requested_tokens`, `estimated_tokens`, `within_budget`, `remaining_tokens`, and
`reserved_budget`. So the honest figure at the selection stage is
`estimated_tokens`; there is no true measured return to record.

### Change

- `src/semidx/core.clj` — selection payload now reads `:returned_tokens` from the
  same real key `expand`/`detail` use (`[:budget_summary :returned_tokens]`),
  which is absent (`nil`) at the selection stage, instead of duplicating
  `estimated_tokens`. `estimated_tokens` remains the selection-stage cost.
  Comment added explaining the semantics.
- `test/semidx/runtime/usage_metrics_test.clj` — added
  `resolve-context-does-not-fabricate-returned-tokens-test`: selection records a
  positive `estimated_tokens` and a `nil` `returned_tokens`; expand records a
  non-negative measured `returned_tokens`.

### Semantics after fix

`returned_tokens` present ⟺ a stage produced a measured return (expand, detail).
`returned_tokens` absent/`nil` ⟺ selection stage; use `estimated_tokens` as its
cost. The benchmark aggregator (Stage 3) must consume `estimated_tokens` for the
selection stage and `returned_tokens` for expand/detail.

### Verification

- REPL (`clojure -M:nrepl`, port 49244): confirmed post-fix selection event
  payload has `returned_tokens = nil`, `estimated_tokens = 153`,
  `reserved_tokens = 180`.
- New test: 3 assertions, 0 failures.
- Existing `library-usage-metrics-flow-test`: 29 assertions, 0 failures.
- Full suite `clojure -M:test`: 289 tests, 1947 assertions, 0 failures, 0 errors.

### Notes / follow-up

- A deeper option — surfacing the pipeline's real measured selection-packet
  tokens (computed at MCP projection but not in the core `result`) into
  `retrieval.clj`'s result — was deliberately not taken. It is a larger change to
  a large file and is unnecessary: `estimated_tokens` is an honest selection-stage
  cost. Revisit only if the benchmark needs measured (not estimated) selection
  cost.
