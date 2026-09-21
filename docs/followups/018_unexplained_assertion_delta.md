---
title: "106 assertion records appeared with no accounted cause"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-20"
---

# 106 Assertion Records Appeared With No Accounted Cause

## Classification

`process_defect`

## Source

Measured in
[Plan 012 Stage 6](../reports/012_java_semantic_quality_without_query_regression_progress.md#one-delta-this-stage-did-not-explain),
which assigned it to Stage 7. Stage 7 restated it as unexplained and closed the
plan, leaving it with no owner; the post-closure
[review](../reports/012_java_semantic_quality_without_query_regression_progress.md#post-closure-review-2026-09-20)
split it out of
[Follow-up 017](017_plan_012_external_evidence_reproducibility.md) so that it
has one.

## Current Behavior

Indexing `apache/dubbo` at `df9c5e1` before and after the Plan 012 static-call
implementation, whole-graph and in `ReleaseFast`:

| Measurement | Before (`384507e`) | After (`8a1f083`) | Delta |
| --- | ---: | ---: | ---: |
| Definitions | 26,509 | 26,509 | 0 |
| Recorded assertions | 230,753 | 230,859 | **+106** |
| Current facts | 90,439 | 92,759 | +2,320 |
| Current unresolved | 140,314 | 138,100 | −2,214 |

2,214 claims converted from unresolved to fact, which the reason-family table
accounts for in full. The remaining 106 facts are assertion records that did not
exist before rather than conversions of records that did.

What Stage 6 ruled out by measurement: nondeterminism (the run repeats exactly),
diagnostics (59,022 in both), entity churn (26,509 definitions in both),
references (every bucket identical), and stale assertions (zero in both). It
also does not appear at module scale — `dubbo-common` alone gives +1,402 facts,
−1,402 unresolved and **no** change in recorded assertions — so it is tied to
reanalysis across the whole batch rather than to the resolution rule itself.

That last observation is the useful one and the one nobody has followed. A
batch-wide reanalysis is exactly where Plan 012 added machinery: the class-shape
aspect channel, the reader hints, and the provider dependencies a resolved call
declares. A unit reanalyzed a second time within one batch re-emits its claims,
and whether that can add assertion records rather than replace them is a
question about `core.reconcile`, not about Java.

## Why Deferred

It is 0.05% of the graph, no unresolved claim is missing because of it, and
every committed lane is green. It was deferred at the time because the plan was
closing and the delta changed no claim the plan made.

It is worth keeping because it is the one measured number in Plan 012 that
nothing explains, and an unexplained difference in what the write path records
is the kind of thing that stops being small once persistence exists.

## Acceptance Direction

Two routes, and the second is the cheaper one to try first.

- **Locally.** Reanalyze one unit twice in a batch and compare the graph's
  recorded assertion count against reanalyzing it once. If a second pass within
  one batch can add records rather than replace them, the delta is reproducible
  without any clone and this entry becomes a defect in the write path with a
  fixture to prove it.
- **Externally.** Re-run the whole-graph before/after probe on a clone of
  `apache/dubbo` at `df9c5e1` and bisect the 106 by assertion kind and producer.
  The measurement needs the harness
  [Follow-up 017](017_plan_012_external_evidence_reproducibility.md) owns.

Note that [Follow-up 015](015_unit_path_change_does_not_reanalyze.md) added
another way for a unit to be analyzed twice in one batch, and
[Follow-up 016](016_java_static_call_rule_narrow_gaps.md) changed what the rule
answers. Re-measure rather than assume the 106 is still 106.

## Required Tests

- A unit reanalyzed twice inside one batch leaves the same number of recorded
  assertions as one reanalyzed once, or the difference is named and is what the
  graph intends.
- Whatever the cause turns out to be, it is stated in the report that owns the
  external measurement rather than left in a residual-risk list.
