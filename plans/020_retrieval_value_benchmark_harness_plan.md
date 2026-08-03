---
title: "Retrieval Value Benchmark Harness Plan"
doc_type: "architecture_plan"
lifecycle: "active"
status: "draft"
agent_action: "reference_for_context"
updated: "2026-08-02"
---

# Architecture Plan: Retrieval Value Benchmark Harness

This plan operationalizes the falsifiable value hypothesis in
[`SPEC.md`](../SPEC.md) §5.1: turn one-off token measurements into a
reproducible, pre-registered benchmark that compares semidx retrieval against
cheap baselines on real repositories, measuring **task success per unit of
tokens and time**.

It is the reusable measurement substrate. It does not itself claim semidx is
better; it makes that claim testable.

## Decision Boundary

- [`SPEC.md`](../SPEC.md) §5.1 is the decision of record for what "worth it"
  means. This plan builds the evidence pipeline for it; it does not set the win
  threshold (owner-set, pre-registered per Stage 0).
- Boundary vs [`plans/019`](./019_llm_one_shot_context_delivery_and_evaluation_plan.md):
  019 owns the one-shot `get_context` delivery surface and its comparison
  fixtures; **020 owns the three-arm real-repo measurement harness and the
  token/success aggregation substrate.** 019's comparison is one consumer of
  020's substrate. Where 019 measures one-shot vs staged, 020 measures semidx
  (staged or one-shot) vs non-semidx baselines.
- Additive only. No change to public retrieval contracts. Reuses the existing
  usage-metrics sink, feedback surface, and evaluation-command patterns.

## Goal

Convert observations such as "~40k tokens on a cold repo without the index vs
~3.4–3.7k with it" into reproducible, falsifiable evidence:

- three arms — **A** semidx, **B** a competent `rg` + targeted-read agent, **C**
  a no-index agent;
- measured on task success, false negatives, wall-clock, tool calls, and tokens;
- against a fixed real-repo task suite;
- with the success/failure threshold fixed **before** the first run.

## Verified current state (grounded)

Metric collection on the semidx side already exists and persists; the gap is the
harness and aggregation layer.

| Capability | Status | Evidence |
| --- | --- | --- |
| Per-op token cost recorded into event `:payload` | present | `src/semidx/core.clj:207` (`resolve-context`), `:267` (`expand-context`) |
| Event schema (first-class cols + `payload`) | present | `src/semidx/runtime/usage_metrics.clj:54` (`normalize-event`) |
| Postgres persists `payload` as `jsonb` (round-trips) | present | `usage_metrics.clj:248` (`PostgresUsageMetrics`, `semantic_usage_events.payload jsonb`), read at `:434` (`postgres-events`) |
| Daily rollups (counts, latency, outcomes) — **no tokens** | present, no tokens | `usage_metrics.clj:248` (`semantic_usage_daily_rollups`) |
| Task success / ground truth capture hook | present, data external | `record-feedback!` → `semantic_usage_feedback` (`feedback_outcome`, `ground_truth_unit_ids/paths`) |
| Agent total session tokens (e.g., 40k / 3.5k) | **missing** | not observable by the runtime; host/harness only |
| Three-arm A/B/C orchestration | **missing** | — |
| Success-per-token aggregator across arms | **missing** | — |

Known fidelity bug: in `resolve-context` the event payload sets
`:returned_tokens` to `estimated_tokens` (`src/semidx/core.clj:207`), while
`expand-context` records the real `:returned_tokens`. The aggregator must either
consume the fixed value (Stage 1) or treat selection-stage `returned_tokens` as
an estimate.

## Scope

In:

- A three-arm benchmark harness (A semidx / B competent `rg`+read / C no-index)
  driving the same task on the same real repository.
- Capture of agent-side totals the runtime cannot see: total session tokens,
  wall-clock, tool-call count — supplied by the harness/host.
- Per-task outcome recording via `record-feedback!` with a shared `task_id` and
  ground-truth unit ids/paths.
- An aggregator evaluation command that joins `semantic_usage_events.payload`
  (tokens) and `semantic_usage_feedback` (outcome) by `task_id`, computing
  success-per-token per arm and applying the pre-registered stop rule.
- Fix of the `returned_tokens` fidelity bug plus a regression test.
- A real-repo task-suite definition, including at least one external repository
  (not semidx itself) to avoid self-tuning bias.

Out:

- No new public retrieval contract, and no change to ADR-024 staged semantics.
- No LLM as source of truth; no general-purpose RAG.
- No modelling of baseline agents' internal prompting beyond token/success
  capture.
- No promotion of `SPEC.md` §5.1 to `[committed]` until real evidence passes.

## Stages

Each stage ends with a commit and a progress-log update under `reports/`.

### Stage 0 — Pre-register metric, then pilot-then-lock the threshold

The provisional *moderate* threshold is recorded in `SPEC.md` §5.1: arm A uses
≥50% fewer tokens (≥2×) than the competent `rg`+read baseline at task success
within 5 percentage points of it, wall-clock ≤ 1.5× baseline, over ≥30 tasks
including ≥1 external repository.

Because a threshold chosen after seeing results cannot falsify anything, lock it
in two steps:

1. **Calibration pilot** (5–10 tasks): measure only the competent-baseline token
   cost and the success-metric noise floor. This produces no verdict.
2. **Lock**: fix the final threshold as "cheaper than the baseline by more than
   the measured noise at parity success", then run scoring. Never adjust the
   threshold after scoring begins.

### Stage 1 — Fidelity fix

Fix `resolve-context` `:returned_tokens` to record the true returned figure (or
an explicitly named estimate field). Add a regression test asserting selection
and expand stages report consistent token semantics.

### Stage 2 — Task suite + three-arm harness

Define the task suite (≥ a small fixed set spanning task types) and at least one
external repo. Build the harness that runs each task through A/B/C, tags every
semidx call and every outcome with a shared `task_id`, and writes outcomes via
`record-feedback!`.

### Stage 3 — Aggregator command

Add an evaluation command (pattern: `run-weekly-review-report-command` in
`src/semidx/runtime/evaluation.clj`) that joins events `payload` tokens and
feedback outcomes by `task_id`, emits per-arm success-per-token, and applies the
Stage 0 stop rule. In-memory sink path must work without PostgreSQL.

### Stage 4 — First real-repo run and evidence write-back

Run the suite, produce the report, and write the result back into `SPEC.md`
§5.1. If the success signal is met, retag the phase; if the failure signal is
met, record the kill-criterion trigger.

## Metric definition

- **Primary (fix-quality variant)**: at equal-or-better task success, the
  percentage token reduction of arm A vs the best cheap baseline (B, then C).
- **Guardrail**: wall-clock of A no worse than the baseline by more than a fixed
  factor (the staged round-trip tax; relieved by one-shot per plans/019).
- **Statistical floor**: significance across the suite (≥ N tasks × seeds;
  non-overlapping confidence, or an agreed test).
- **Token source**: per-event `payload` in `semantic_usage_events` — **not**
  `semantic_usage_daily_rollups` (no token columns). Plus harness-supplied agent
  session totals.
- **Success source**: `feedback_outcome` in `semantic_usage_feedback`.

## Stop / kill rules

Directly inherit `SPEC.md` §5.1:

- **Success signal**: A beats the baselines on success-per-token by the
  pre-registered margin, above the statistical floor.
- **Failure signal**: A does not beat `rg` + reading files (and `rg` + LSP where
  available) on that ratio → SPEC §5.1 kill-criterion (narrow to Clojure-first).

## Risks

- **Strawman baseline.** The 40k figure is likely a cold broad-read, not a
  competent `rg`+read agent. Arm B must be genuinely competent or a win is an
  artifact. This is the main threat to validity.
- **Self-repo bias.** Measuring only on semidx's own repo overstates the result;
  at least one external repo is required.
- **Fidelity.** Until Stage 1, `resolve-context` `returned_tokens` is an
  estimate.
- **PostgreSQL optionality.** The aggregator must not require Postgres; the
  in-memory sink path is first-class.

## Definition Of Done

- The provisional threshold and metric are recorded in `SPEC.md` §5.1, and the
  final threshold is locked after the Stage 0 calibration pilot, before scoring.
- The `returned_tokens` fidelity bug is fixed with a regression test.
- The harness produces a reproducible three-arm success-per-token report on at
  least one external real repository.
- `SPEC.md` §5.1 can be retagged (pass) or its kill-criterion recorded (fail)
  from that report.

## References

- [`SPEC.md`](../SPEC.md) — value hypothesis §5.1 (decision of record).
- [`plans/018`](./018_semantic_provider_authority_migration_plan.md) — provider
  authority (fact quality).
- [`plans/019`](./019_llm_one_shot_context_delivery_and_evaluation_plan.md) —
  one-shot delivery and its comparison fixtures (consumer of this substrate).
- [`adr/024-make-compact-first-staged-retrieval-the-canonical-public-flow.md`](../adr/024-make-compact-first-staged-retrieval-the-canonical-public-flow.md)
- `src/semidx/core.clj` — `resolve-context` / `expand-context` event payloads.
- `src/semidx/runtime/usage_metrics.clj` — sink, event/feedback tables, rollups.
- `src/semidx/runtime/evaluation.clj` — evaluation-command pattern.
