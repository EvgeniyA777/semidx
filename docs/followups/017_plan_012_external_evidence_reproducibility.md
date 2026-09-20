---
title: "Plan 012 external numbers are not reproducible"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-20"
---

# Plan 012 External Numbers Are Not Reproducible

## Classification

`process_defect`

## Source

Found in the post-closure review of
[Plan 012](../plans/012_java_semantic_quality_without_query_regression.md),
recorded in its
[progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md#post-closure-review-2026-09-20).
It carried forward two items the plan itself recorded: the Stage 6 decision not
to commit the classification script, and the 106-assertion delta Stage 6
assigned to Stage 7. The second is now
[Follow-up 018](018_unexplained_assertion_delta.md); this entry is about the
numbers being repeatable.

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

## What Has Been Done

A harness now exists and is committed: `scripts/java-claim-sample.py`. It is a
developer measurement tool, not a build lane and not a conformance check; no
`zig build` step refers to it. It drives the real MCP stdio server over the
`2026-07-28` protocol and asks only what a consumer could ask.

**The sample no longer depends on the script.** Its selection is specified in
the script's own docstring and repeated here, because a procedure that lives
only in one implementation is the thing this entry is about:

    key  = "<unit path>\n<start line>\n<role>\n<name>"    for every definition
    rank = sha256(seed + "\n" + key)                       as lowercase hex
    the sample is the first `size` definitions ordered by (rank, key)

No language runtime's random number generator takes part, so a reimplementation
in any language draws the same definitions from the same seed. That is what
Stage 0's record could not offer: it named the seed and the size and left the
selection to a script nobody kept.

**A decomposition that loses a family now says so.** Every unresolved call is
put in exactly one reason family by matching the frontend's own words, a claim
matching none is counted under `unclassified` and its explanation printed, and
the report states whether the families sum to the whole. Stage 7's table listed
eight families and was silent about three; a sum that closes was the only
evidence those three were zero. This makes that evidence explicit, and makes a
reworded reason visible instead of silent.

**Verified on the inputs available here**, which do not include the measured
clone:

| Check | Result |
| --- | --- |
| `--root fixtures`, Java | 29 definitions, 36 claims, families sum to the whole, `unclassified` 0 |
| A tree written to reach every family | 16 unresolved calls split across 14 of the 17 families, `unclassified` 0 |
| The three families that stayed zero | `target_supertypes_unknown`, `target_shape_not_read`, `target_static_unrecorded` — the three [Follow-up 016](016_java_static_call_rule_narrow_gaps.md) records as unreachable from ordinary source |
| Two runs of one seed | byte-identical reports |
| A different seed | a different sample |
| `--root . --language zig` | 117 unresolved calls, all `unclassified`, each explanation printed — the miss is loud |

## Why It Is Still Open

The harness is new, so it produces a **new** baseline rather than confirming the
old one. Stage 0's selection was never recorded and cannot be recovered, so the
1,200 definitions Plan 012 measured are not the 1,200 this script draws, and its
headline numbers — 6,710 claims, 5,662 unresolved calls, 174 then 313 call
facts, 139 static-call facts — remain unverifiable by anyone.

Nothing here has been run against `apache/dubbo` at `df9c5e1`: there is no clone
in this environment. Until there is, the entry stays open, because closing it
would assert a check that did not run.

There is also a number to re-take rather than confirm.
[Follow-up 016](016_java_static_call_rule_narrow_gaps.md) tightened the static
call rule after 139 was measured, so the next run answers a different question
than the old one did, and the difference is the measurement 016 owes.

## Acceptance Direction

Close this entry when a run against a clone of `apache/dubbo` at `df9c5e1`
records a new baseline in a report that owns it, stating plainly that it
replaces Plan 012's numbers rather than confirming them.

## Required Tests

This entry asks for reproducibility, not behavior, so its checks are not unit
tests:

- `scripts/java-claim-sample.py --root <clone of apache/dubbo at df9c5e1>`
  completes and its families sum to the whole with `unclassified` at zero.
- The same command, run twice, produces identical reports.
- A second person, given only the selection rule above and the seed, draws the
  same sample as the script.
- The new baseline is recorded in a report, beside a statement that Plan 012's
  139 was measured under the looser rule 016 replaced.
- No build lane refers to the script: `zig build test`, `zig build test-mcp`,
  `zig build dogfood` and `zig build preview-gate` are unchanged by it.
