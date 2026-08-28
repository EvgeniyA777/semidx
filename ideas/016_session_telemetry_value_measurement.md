---
title: "Session Telemetry as the Value Measurement"
doc_type: "idea"
lifecycle: "concept"
status: "draft"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-08-28"
---

# Session Telemetry as the Value Measurement

Replacement core idea for how semidx proves its worth. It supersedes the
measurement approach of
[`plans/020`](../plans/020_retrieval_value_benchmark_harness_plan.md), which is
paused (see [`reports/021`](../reports/021_retrieval_value_benchmark_harness_progress_log.md)).

## The idea

Measure semidx during real work instead of staging an experiment beside it.

Every session already spends tokens. While the work happens, record what each
semidx call cost, whether it actually helped, and which task and process it
belonged to. Aggregate by task and by process, then analyse the accumulated
record. semidx worked — count the tokens. semidx did not work — count the
tokens anyway. The evidence is the sum of real sessions, not a controlled run.

The unit of observation is the **task attempt inside a real session**, not a
corpus entry. Nothing is authored for the purpose of being measured.

## Why this instead of the four-arm harness

- **The corpus problem disappears.** A frozen 9-task suite measures what its
  author chose to include; a live stream measures what the repository actually
  gets asked. Corpus bias was the paused plan's own listed risk.
- **No synthetic agent is required.** The paused design needed a purpose-built
  agent to be a credible baseline, which put an LLM tool loop and a provider
  client inside a code-indexing library. Passive telemetry needs neither.
- **No provider spend to get started.** The four-arm design cannot produce a
  single number without paying for baseline arms.
- **Most of the machinery already exists.** `semantic_usage_events` records per
  stage cost and confidence, `semantic_usage_feedback` records outcomes,
  rollups and the weekly review report already aggregate them, and the staged
  cost semantics were fixed in `plans/020` Stage 1 (selection carries
  `estimated_tokens`; expand and detail carry measured `returned_tokens`).

## What must be recorded

| Signal | Source | State |
| --- | --- | --- |
| semidx packet cost per stage | `semantic_usage_events.payload` | exists |
| retrieval confidence, result status, degradations | `semantic_usage_events` | exists |
| task and session identity | usage context (`session_id`, `task_id`) | exists, but real sessions must actually set it |
| worked / did not work | `semantic_usage_feedback.feedback_outcome` | exists as a mechanism; nobody produces the verdict yet |
| failure shape when it did not work | `retrieval_issue_codes` | vocabulary exists; needs to reflect real failures |
| the agent's own token spend | host session transcript, not semidx | **missing** |

Two gaps decide whether this idea works at all.

**Who says it worked.** A feedback record needs an author. Candidates: the
agent self-reports at the end of a task, the human marks it, or it is inferred
from behaviour (the agent asked semidx and then read the same files by hand
anyway — that is a miss; the agent answered directly from the packet — that is a
hit). Behavioural inference is the only option that scales, and it is also the
one that can silently encode a wrong definition of success. This needs a
decision before anything is built.

**Whose tokens.** semidx can only see the tokens it returned; it cannot see what
the host model was billed. Total session cost lives in the host's transcript
(for Claude Code, the session `.jsonl` usage records that the `ccbox` skill
already reads). Correlating semidx events with host session usage is the piece
that turns "packet tokens" into "what the session actually cost".

## What this can and cannot answer

It can answer, from real work:

- what semidx costs per task, and how that distribution behaves in the tail;
- how often it helps, and the taxonomy of how it fails;
- whether either trend improves as the product changes.

It cannot answer, on its own: **what the same work would have cost without
semidx.** There is no counterfactual in an observational record, and the
comparison is confounded — semidx gets asked about the tasks somebody thought it
would suit, and those are not average tasks. This is the honest cost of dropping
the arms.

If a causal claim is still wanted, the cheapest bridges are:

- **Deliberate abstention**: for a sampled fraction of queries semidx returns
  nothing and the agent proceeds without it. Same session, same task, same
  model, no separate corpus and no separate agent. This is the smallest change
  that recovers a real baseline.
- **Cutover comparison**: the same repository and task mix before and after a
  capability lands, which is weaker but free.

`SPEC.md` §5.1 currently states its success and failure signals comparatively
(arm A against a competent `rg` baseline). If session telemetry becomes the
primary evidence path, that section has to be rewritten to state what
observational evidence would count as a pass — otherwise the project keeps a
verdict rule that no planned measurement can produce. That rewrite is a
decision of record and belongs to the owner.

## Smallest useful slice

1. Make real sessions set `session_id` and `task_id` so events group into task
   attempts at all.
2. Decide and record what "worked" means; write it down before collecting, not
   after looking.
3. Correlate one host session transcript with its semidx events end to end, and
   see whether the join holds up on real data.
4. Only then aggregate, and only report distributions, never a verdict.

## Open questions for the owner

- Who authors the worked / did not work verdict, and is behavioural inference
  acceptable?
- Is a comparative claim still wanted, and if so, is deliberate abstention
  acceptable in real sessions?
- Which surfaces count: only the MCP path used interactively, or library and
  HTTP consumers as well?
- Do the paused four-arm artefacts stay available as a fallback, or does the
  comparative approach get dropped outright?

## References

- [`plans/020`](../plans/020_retrieval_value_benchmark_harness_plan.md) — paused comparative design.
- [`reports/021`](../reports/021_retrieval_value_benchmark_harness_progress_log.md) — what was delivered before the pause.
- [`SPEC.md`](../SPEC.md) §5.1 — the value hypothesis and its current verdict rule.
- `src/semidx/runtime/usage_metrics.clj` — events, feedback, rollups, reports.
