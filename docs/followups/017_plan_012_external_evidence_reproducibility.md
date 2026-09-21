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

A harness now exists and is committed: `src/claim_sample.zig`, run as
`zig build claim-sample -- --root <dir>`. It is a developer tool, not a lane and
not a conformance check: `test`, `test-mcp`, `dogfood` and `preview-gate` do not
build it, no git hook or `.mcp.json` entry names it, and no test asserts against
its output.

It is written in Zig because the toolchain is already required and nothing else
is — [tooling.md](../agent-policy/tooling.md#runtime-budget-for-repository-tooling)
owns that rule. The first version of this harness was written in Python for
speed, which added an interpreter to a project that needed none and was not
recorded as a decision; it was replaced before the entry was written up, and the
rule was written so the next tool does not repeat it.

It reads the published snapshot rather than the MCP preview. The preview is a
projection of that snapshot, so the claims are the same ones, but a response
budget can truncate an answer and a measurement should not have to reason about
where a page ended. One visible consequence: the snapshot reports `defines`
claims that `semidx_references outgoing` does not, so the claim totals here are
larger than a run through the preview would report, while `calls` and
`references` agree claim for claim.

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

The families, in the order they are tried — the first fragment a claim contains
wins, so a fragment that is a substring of another comes after it:

| Family | Fragment of the frontend's explanation |
| --- | --- |
| `receiver_not_simple_name` | qualified by a receiver this frontend does not resolve |
| `nested_class_body` | class body declared in the method |
| `receiver_bound` | is declared here as a binding, so it is read as a value |
| `on_demand_static_import` | imports static members on demand |
| `enclosing_supertypes` | a field it may inherit |
| `receiver_reaches_no_class` | the receiver is not read as a class |
| `target_supertypes` | declares supertypes, so a method of this name it may inherit |
| `target_supertypes_unknown` | carries no record of whether it declares supertypes |
| `target_shape_not_read` | whose current shape this analysis did not read |
| `target_no_method` | declares no method of this name |
| `target_overloaded` | methods of this name, and overloads are not resolved |
| `target_not_static` | is not static, so naming it through the class |
| `target_static_unrecorded` | carries no record of whether it is `static` |
| `target_inaccessible` | outside the access this frontend resolves across classes |
| `unqualified_no_method` | no method of this name is declared in the enclosing class |
| `unqualified_overloaded` | methods of this name are declared in the enclosing class |
| `unqualified_supertypes` | a method of this name it may inherit could be the target |

Anything else is `unclassified`. The fragments are the frontend's own words, so
rewording a reason in `src/frontends/java.zig` moves its claims there rather
than losing them quietly.

**Verified on the inputs available here**, which do not include the measured
clone:

| Check | Result |
| --- | --- |
| `--root fixtures`, Java | 29 definitions, 12 call facts and 4 unresolved calls, families sum to the whole, `unclassified` 0 |
| A tree written to reach every family | 16 unresolved calls split across 14 of the 17 families, `unclassified` 0 |
| The three families that stayed zero | `target_supertypes_unknown`, `target_shape_not_read`, `target_static_unrecorded` — the three [Follow-up 016](016_java_static_call_rule_narrow_gaps.md) records as unreachable from ordinary source |
| Two runs of one seed | byte-identical reports |
| A different seed | a different sample |
| `--root . --language zig` | 228 unresolved calls, all `unclassified`, five explanations printed — the miss is loud, and no Zig families are written yet |

## The Baseline Now Exists

[Plan 013 Stage 0](../reports/013_unresolved_mentions_from_the_callee_anchor_progress.md#stage-0-reproducible-baseline)
ran the harness against a clone of `apache/dubbo` at `df9c5e1`, recorded the
clone path, the commit, the seed and every number, and owns the result. What it
found, on 2026-09-20 at `8025a0c`:

| | Plan 012 close (`8a1f083`) | Now (`8025a0c`) |
| --- | ---: | ---: |
| Sampled outgoing claims, 1,200 definitions | 6,710 | 7,283 |
| `calls` facts / unresolved in that sample | 313 / 5,523 | 265 / 5,281 |
| Whole-graph facts / unresolved | 92,759 / 138,100 | 92,637 / 138,222 |
| Whole-graph unresolved calls | 118,349 | 118,471 |

The sample rows **replace** Plan 012's rather than confirm them: the harness
draws by `sha256(seed + "\n" + key)` rank, and the 1,200 definitions Plan 012
measured were drawn by a script nobody kept, so its headline numbers — 6,710
claims, 5,662 then 5,523 unresolved calls, 174 then 313 call facts, 139
static-call facts — remain unverifiable by anyone and now stand beside a
baseline that is not.

The whole-graph rows are comparable, because the harness sampling all 26,509
definitions is a census. Every family matches Plan 012's whole-graph table to
the unit except the 122 claims that [Follow-up 016](016_java_static_call_rule_narrow_gaps.md)
moved from fact to unresolved, which are accounted for claim by claim in the
Stage 0 log. That is the re-take 016 owed.

## Why It Is Still Open

One required check did not run: **nobody reimplemented the selection rule and
drew the same sample independently.** Two runs of the same binary produced
byte-identical reports, which proves determinism, not that the rule written down
here is enough to re-derive the sample without this repository's build. Until
someone draws the sample from the rule alone, the claim this entry exists to
make — that the procedure, not the program, is the evidence — is untested.

## Acceptance Direction

The baseline this asked for is recorded and owned by the Plan 013 Stage 0 log.
What remains is narrow: close this entry when someone draws the sample from the
selection rule alone — without running `semidx-claim-sample` — and gets the
sample the harness gets.

## Required Tests

This entry asks for reproducibility, not behavior, so its checks are not unit
tests:

- ~~`zig build claim-sample -Doptimize=ReleaseFast -- --root <clone of
  apache/dubbo at df9c5e1>` completes and its families sum to the whole with
  `unclassified` at zero.~~ Done: 118,471 unresolved calls, families sum to the
  whole, `unclassified` 0.
- ~~The same command, run twice, produces identical reports.~~ Done.
- **A second person, given only the selection rule above and the seed, draws the
  same sample as the script.** Not done; this is what keeps the entry open.
- ~~The new baseline is recorded in a report, beside a statement that Plan 012's
  139 was measured under the looser rule 016 replaced.~~ Done, in the Plan 013
  Stage 0 log.
- ~~No build lane refers to the script: `zig build test`, `zig build test-mcp`,
  `zig build dogfood` and `zig build preview-gate` are unchanged by it.~~ Still
  true, and true of `semidx-designator-shape` beside it.
