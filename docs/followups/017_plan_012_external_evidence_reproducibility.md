---
title: "Plan 012 external evidence is not reproducible"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-20"
---

# Plan 012 External Evidence Is Not Reproducible

## Classification

`process_defect`

## Source

Found in the post-closure review of
[Plan 012](../plans/012_java_semantic_quality_without_query_regression.md),
recorded in its
[progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md#post-closure-review-2026-09-20).
It carries forward two items the plan itself recorded: the Stage 6 decision not
to commit the classification script, and the 106-assertion delta Stage 6
assigned to Stage 7.

## Current Behavior

### The harness is not committed, and the log does not fully describe it

Plan 012's headline numbers — 139 static-call facts, the decomposition of 4,624
calls into eight families, the accepted-access denominator — all come from an
offline harness that samples definitions and classifies unresolved explanations.
Stage 6 recorded the decision not to commit it, "in keeping with this plan's
rule that external measurements are evidence rather than conformance", and
argued it was rebuildable from the log.

Stage 7 then had to rebuild it, because Stage 0's copy was gone. It reproduced
Stage 0's table to the unit, which is strong evidence that the rebuild was
faithful. The cost of the decision is therefore no longer hypothetical: it is
one full rebuild, paid once already.

What the log records is the repository and commit (`apache/dubbo` at `df9c5e1`),
the sample size (1,200 of 26,509 Java definitions), the seed (`20260918`), and
the protocol (`semidx_references outgoing` per sampled definition, one process
per run). What it does not record is how the seed selects the sample: which
enumeration order the 26,509 definitions are taken in, and which generator turns
the seed into indices. Two people following the log will draw two different
samples. `scripts/` holds no sampling or classification script at `6a47ba5`.

Plan 013 and Follow-ups 013 and 014 all name this harness as the way their
thresholds get re-measured.

### The 106-assertion delta was assigned and not discharged

Stage 6 measured that current facts rose by 2,320 while current unresolved fell
by 2,214, leaving 106 assertion records that did not exist before. It ruled out
nondeterminism, diagnostics, entity churn, references, and stale assertions by
measurement, showed it does not appear at single-module scale, and wrote:
"Stage 7 owns the full external probe and should account for it there."

Stage 7 restated it as unexplained and closed the plan. It is 0.05% of the
graph and no unresolved claim is missing because of it, but it is an unexplained
difference in what the write path records, it now has no owner, and explaining
it needs exactly the external probe that is not committed.

## Why Deferred

Neither item changes a claim Plan 012 makes. The measurements are internally
consistent — the decomposition sums to its whole, the before/after totals agree
with the sampled deltas — and the lanes that gate behavior are committed and
green.

They are recorded rather than acted on because committing an external harness is
a policy question this plan should not settle alone: the register's own
distinction between evidence and conformance is what kept it out, and the fix is
either to commit it as a developer tool that no lane depends on, or to write the
sampling algorithm into the log precisely enough that the seed reproduces the
sample.

## Acceptance Direction

The next plan that needs an external Java measurement should settle this before
it measures, because it will otherwise rebuild the harness a third time.

- **Make the sample reproducible.** Either commit the sampler under `scripts/`
  as a developer tool with no build-lane dependency, or record in the owning
  report the exact enumeration order and generator the seed drives. The test is
  falsifiable: a second person, given only the record, must draw the same 1,200
  definitions.
- **Account for the 106.** The probe that explains it is the same whole-graph
  before/after run Stage 6 used. Either name the cause, or reclassify it as a
  known write-path behavior with its own entry, rather than leaving it in a
  closed plan's residual risk.
- **Decide the rule once.** If external classification harnesses are evidence
  and not conformance, say where they live so the decision does not have to be
  re-taken per plan.

## Required Tests

This entry asks for reproducibility, not behavior, so its checks are not unit
tests:

- Running the recorded procedure on a fresh clone of `apache/dubbo` at
  `df9c5e1` reproduces the Stage 7 baseline table — 6,710 claims, 5,662
  unresolved calls, 174 call facts — against pre-Plan-012 code.
- The same procedure reproduces the current table: 5,523 unresolved calls, 313
  call facts, 139 of them static-call facts.
- If the sampler is committed, no build lane depends on it and `zig build test`,
  `zig build test-mcp`, `zig build dogfood` and `zig build preview-gate` are
  unchanged by its presence.
