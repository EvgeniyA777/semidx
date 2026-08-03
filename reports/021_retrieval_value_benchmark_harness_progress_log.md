---
title: "Retrieval Value Benchmark Harness Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-03"
---

# Progress Log: Retrieval Value Benchmark Harness

Companion log for
[`plans/020_retrieval_value_benchmark_harness_plan.md`](../plans/020_retrieval_value_benchmark_harness_plan.md).

## Stage Status

| Stage | Status |
| --- | --- |
| 0 — Pre-register arms/run identity/metric, pilot-then-lock threshold | pre-registration sub-gate completed (see `reports/023_retrieval_value_benchmark_preregistration.md`); calibration pilot and final-lock pending |
| 1 — Fidelity fix (`returned_tokens`) | completed |
| 2 — Task suite + four-arm harness | not started |
| 3 — Aggregator command | not started |
| 4 — First real-repo run + evidence write-back | not started |

## Stage Routing Amendment (2026-08-03)

- `plans/020` now records a recommended executor, primary model, and effort for
  every stage. High effort is allowed and recommended for preregistration,
  aggregation, and evidence-verdict decisions where an error could invalidate
  the experiment or trigger the wrong kill decision.
- Every future stage closure must record a
  `NextStageRoutingRecommendation` after reading the candidate next stage,
  dependent-plan gates, progress/MEMORY/SPEC state, completed diff and checks,
  file ownership, and current model/quota constraints. A high-effort
  recommendation must include a concrete `effort_justification`.
- Stage 1 completed before this protocol. No retrospective routing result is
  invented; Stage 0 closure or Stage 2 admission produces the first handoff.

### Routing amendment verification

- `git diff --check`: passed.
- English-only scan over all revised documents: passed (no Cyrillic matches).
- Runtime tests were skipped because this amendment changes documentation and
  execution routing only; no source, contract artifact, or generated output was
  modified.
- CCC artifacts were not refreshed because the amendment does not require new
  compression output and `RULES.md` forbids routine per-task refreshes.

## Architecture Review Findings (accepted and fixed in plan documents)

The cross-plan review is recorded in
[`reports/022_latest_active_plans_architecture_review.md`](./022_latest_active_plans_architecture_review.md).

| Finding | Disposition | Plan-level fix |
| --- | --- | --- |
| `plans/019` and `plans/020` duplicated corpus/harness ownership | accepted, fixed | `plans/020` is the exclusive benchmark-substrate owner; `plans/019` supplies one-shot adapters only |
| Benchmark arms, cost terminology, and repeated-run identity were not preregistration-safe | accepted, fixed | A/B/C/D arms, B comparator, `BenchmarkRun`, `TaskAttempt`, and attempt-first aggregation are explicit |
| Arm D and the per-arm policy boundary were underspecified | accepted, fixed | arm roles, shared task prompt, versioned arm-policy bundle, per-attempt policy identity, isolation, cache protocol, and within-run controls are explicit |
| Provider usage adapters could misprice cache writes or reasoning output | accepted, fixed | versioned API/model adapters, cache TTL classes, visible/reasoning/unclassified output, tool charges, raw usage, and immutable price schedules are required |
| One-shot budgets and telemetry could double count | accepted, fixed in dependent plan | `plans/019` now has one top-level response ledger and aggregate/stage accounting scopes |
| Provider arbitration lacked a provider-neutral fact key | accepted, fixed in dependent plan | `plans/018` now gates arbitration on `CanonicalFactKey` and cross-provider identity fixtures |
| Active-plan metadata and continuation guidance were stale | accepted, fixed | `plans/020` is `in_progress`; `plans/007` points at current continuations |

### Architecture review verification

- `git diff --check`: passed.
- English-only scan over all revised documents: passed (no Cyrillic matches).
- `clojure -M:test` before the documentation-only revision: 289 tests, 1947
  assertions, 0 failures, 0 errors; no runtime source changed afterward.
- `clojure -M:ccc check --root .`: reported existing CCC artifacts as stale.
  Regeneration was skipped because this review does not require new compression
  output and `RULES.md` explicitly forbids routine per-task refreshes.

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

## Stage 0 — Pre-registration and Lock (in progress)

### Sub-gate: pre-registration document

Completed. The pre-registration is locked in
`reports/023_retrieval_value_benchmark_preregistration.md`.

Key decisions recorded:

- A/B/C/D arm definitions and verdict roles locked.
- `executor_model` vs `evaluated_provider_model` distinction explicit throughout.
- `BenchmarkRun` and `TaskAttempt` schemas locked; `TaskAttempt` fields use
  `evaluated_*` prefix.
- Cache protocol `implicit_cache_observed_v1`: explicit cache objects forbidden;
  implicit cache reads recorded at Cache Read rate; arm order is randomized or
  counterbalanced and cache variation is observable rather than labeled cold.
- Price schedule `2026-08-03-eligible-v1` covers only eligible evaluated models
  (`gemini-2.5-pro`, `gemini-2.5-flash`). Legacy models (`claude-3-5-sonnet-20240620`,
  `gpt-4o-2024-05-13`) moved to historical-only reference, excluded from v1 verdict.
- Arm D forbidden tools defined once and referenced by both policy and audit rule.
- Calibration pilot and final threshold lock pending.

### Iteration 5 contract amendment

- `plans/020` and this pre-registration now share the same `evaluated_*`
  `TaskAttempt` identity fields; executor-model routing remains separate.
- The cache protocol was renamed from a misleading cold-start claim to
  `implicit_cache_observed_v1`; explicit cache objects remain forbidden.
- Arm D uses a finite tool allowlist plus one finite command-prefix denylist for
  `bash`, and the audit consumes those same lists.
- The Gemini 2.5 eligible schedule expires on 2026-10-16. Pilot/scoring after
  that date requires a new preregistered schedule.

### Iteration 5 verification

- `git diff --check`: passed.
- English-only scan over the amended plan, pre-registration, progress log, and
  `MEMORY.md`: passed (no Cyrillic matches).
- Markdown links added by the amendment point to the official Gemini
  deprecation schedule; existing plan/report links remain unchanged.
- Runtime tests: skipped; this amendment changes plan and benchmark-admission
  documentation only, with no runtime source or contract artifact changes.
- CCC artifacts: not refreshed; `RULES.md` forbids routine per-task refreshes.

### Sub-gate: calibration pilot and final lock

Not started. Must complete before scoring (Stage 4).

### Iteration 4 verification

- `git diff --check`: passed.
- English-only scan (`grep -rnP '[\x{0400}-\x{04FF}]'` over both changed
  files): passed (no Cyrillic matches).
- Runtime tests: skipped; no runtime source was changed.
- CCC artifacts: not refreshed; `RULES.md` forbids routine per-task refreshes.

### NextStageRoutingRecommendation

```text
completed_stage: Stage 0 pre-registration sub-gate
recommended_next_stage: Stage 2 — Task suite + four-arm harness
recommended_executor: Antigravity
recommended_model:
  mechanical_implementation: Gemini 3.6 Flash (medium effort)
  contract_validation: Gemini 3.1 Pro (high effort)
  fallback: Gemini 3.5 Flash
effort: medium (default), high (contract validation only)
effort_justification: >
  High effort is required only for the contract validation pass:
  the cost-normalization adapter must correctly map implicit cache-read
  tokens from each provider's usage response to the Cache Read rate
  in the price schedule, and the aggregation roll-up
  (benchmark_run_id, task_id, arm) is contract-critical for the Phase 1
  verdict. A miscount silently produces wrong cost_usd values.
rationale: >
  plans/020 routing table (line 264) assigns Gemini 3.6 Flash / medium
  for Stage 2. These are executor models inside Antigravity and are
  unrelated to the evaluated_provider_model in TaskAttempt. The price
  schedule does not need to list executor models.
prerequisites_or_blockers: >
  Stage 2 harness may be built now. Stage 4 scoring must not start
  until the calibration pilot (Stage 0 sub-gate 2) is completed and
  the final threshold is locked.
file_ownership_and_conflict_risk: >
  Stage 2 will provisionally create files under benchmark/ or
  src/semidx/runtime/benchmark/. It will also need to read
  src/semidx/runtime/usage_metrics.clj and src/semidx/core.clj to
  conform to existing event schemas. Whether Stage 2 requires writes
  to those files is not yet determined — it depends on whether the
  existing usage-metrics sink can host benchmark events without
  schema changes. This is a risk to surface during Stage 2 admission,
  not a claim resolved here.
fallback_executor_or_model: Gemini 3.5 Flash (per plans/020 line 270)
model_availability_checked_at: >
  deferred — Gemini 3.6 Flash and Gemini 3.1 Pro availability inside
  Antigravity cannot be confirmed by checking ai.google.dev pricing.
  Actual availability will be confirmed at Stage 2 admission by the
  executor. If unavailable, defer to Gemini 3.5 Flash as fallback.
confidence: high (for the routing recommendation itself)
```
