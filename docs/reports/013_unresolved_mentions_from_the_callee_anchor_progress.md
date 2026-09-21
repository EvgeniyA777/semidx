---
title: "Unresolved mentions from the callee anchor progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-20"
---

# 013: Unresolved Mentions From The Callee Anchor Progress

Companion log for
[docs/plans/013_unresolved_mentions_from_the_callee_anchor.md](../plans/013_unresolved_mentions_from_the_callee_anchor.md).

## Current Status

**Stage 0 is complete.** The baseline every later claim is compared against is
recorded below, taken from a named clone at a named commit with named commands.
No frontend, core, or MCP behavior changed in this stage; the only code it added
is one developer-only measurement command that no lane depends on.

The plan's Start Rule asks Stage 0 one question before the rest may run: do the
dominant unresolved families already key on a bare name? **They do not.** Of the
118,471 unresolved Java calls in the clone, **99,103 (83.6%) carry a designator
that is not a name at all** — it is invocation text such as `builder.build()` —
and the designator index holds **53,483 expression keys against 3,492 name
keys**. The stage order stands and Stage 1 may proceed.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Reproducible baseline | Completed | Baseline recorded from `apache/dubbo` at `df9c5e1`: 230,859 assertions, 92,637 facts, 138,222 unresolved, of which 118,471 unresolved calls and 19,751 unresolved references. 83.6% of unresolved call designators are expressions, not names. Five named definitions return 0, 93, 23, 8 and 0 incoming relationships against designator buckets of 1,091, 324, 293, 245 and 221. |
| Stage 1: A designator is a structured name | Not started | — |
| Stage 2: The bucket is the whole walk | Not started | — |
| Stage 3: `unresolved_mentions` in `semidx_references` | Not started | — |
| Stage 4: External re-measure | Not started | — |
| Stage 5: Documentation and closure | Not started | — |

## Stage 0: Reproducible Baseline

### Environment And Inputs

| | |
| --- | --- |
| Zig | 0.16.0, `./scripts/check-zig-version.sh` passes |
| semidx commit | `8025a0c282e239c83fc21fbf531666056a70e4e2`, branch `dev` |
| semidx worktree at stage start | clean |
| Measured clone | `~/.cache/semidx-external/dubbo`, outside this repository |
| Clone commit | `df9c5e13bc014ef492ec20824f8623a5e092a5b1` (`df9c5e1`), authored 2026-09-15 |
| Clone worktree | clean, 0 modified or untracked files |
| Build mode for every measurement | `-Doptimize=ReleaseFast` |
| Sample seed | `20260918`, the seed Plan 012 recorded |

The clone is evidence, not a conformance target: no lane, hook, or `.mcp.json`
entry names it, and nothing in this repository was checked out or branched to
take these numbers.

### The Command Stage 0 Had To Add

Neither committed developer tool reports what a designator holds or how the
index keyed on it is shaped. `semidx-dev` prints graph totals and every
unresolved target as a line of text; `semidx-claim-sample` classifies
*explanations*, not designators. Stage 0 therefore added a third developer-only
command, on the same terms as the other two:

```
zig build designator-shape -Doptimize=ReleaseFast -- --root <dir> [--top <n>]
```

`src/designator_shape.zig`. `zig build test`, `zig build test-mcp`,
`zig build dogfood` and `zig build preview-gate` do not build it, no test
asserts against its output, and no hook or lane names it.

**Its procedure, so the numbers can be re-derived without it** — as
[tooling.md](../agent-policy/tooling.md#runtime-budget-for-repository-tooling)
requires. Index the root, publish one snapshot, and then:

- For every assertion whose resolution is `unresolved` and whose relationship
  target is a designator, group by the language of its source entity, its
  relationship kind, and the **shape** of the designator's bytes.
- A designator is a `simple_name` when every byte is a name byte in that
  language and the first is not a digit; a `qualified_name` when the language's
  separator splits it into two or more simple names; an `expression` otherwise.
- Name bytes are alphanumerics plus `_`, plus `$` for Java, plus the symbol
  constituents `- + * ! ? < > = & % ' . : #` for Clojure; every byte at or above
  `0x80` counts as a name byte. The separator is `.` for Java and Zig and `/`
  for Clojure.
- For the index: `DesignatorAdjacency` holds one bucket of assertion positions
  per distinct designator. Report how many keys it holds, how many positions
  they bucket in total, `byteSize()`, the shape of each key judged in the
  language of the first claim in its bucket, and the largest buckets with the
  number of live definitions carrying that exact name.

The categories are a measurement's vocabulary, not the model's. The graph
stores one string per unresolved target today; this only says what that string
looks like.

### Whole-Graph Baseline

`./zig-out/bin/semidx-dev <clone>` and
`zig build designator-shape -- --root <clone>` agree to the unit:

| | Plan 012 Stage 0 (`384507e`) | Plan 012 close (`8a1f083`) | Now (`8025a0c`) |
| --- | ---: | ---: | ---: |
| Source units | 4,050 | 4,050 | 4,050 |
| Definitions | 26,509 | 26,509 | 26,509 |
| Assertions recorded | 230,753 | 230,859 | 230,859 |
| Current facts | 90,439 | 92,759 | **92,637** |
| Current unresolved | 140,314 | 138,100 | **138,222** |
| Approximate | 0 | 0 | 0 |
| Stale | 0 | — | 0 |
| Diagnostics | — | — | 59,022 |
| Snapshot revision | — | — | 7,292 |

The 122 assertions that moved from fact to unresolved since Plan 012 closed are
accounted for below. Nothing else in the graph moved.

### What A Designator Holds Today

Every one of the 138,222 unresolved assertions has a designator target. None is
in Clojure or Zig: the clone is Java.

| Language | Kind | `simple_name` | `qualified_name` | `expression` | Total |
| --- | --- | ---: | ---: | ---: | ---: |
| java | references | 15,551 | 227 | 3,973 | 19,751 |
| java | calls | 19,368 | 0 | **99,103** | 118,471 |

Two readings this plan is built on:

- **Calls.** 83.6% of unresolved call designators are not names. This is D1's
  subject and the Start Rule's answer: the dominant family does not key on a
  bare name, so the plan's stage order holds.
- **Type references, D2's input.** 4,200 of 19,751 Java type-reference
  designators (21.3%) are not simple names: 227 are qualified names such as
  `java.util.List`, and 3,973 are neither — generic type syntax such as
  `List<String>` is the bulk of that column. D2 leaves them as they are, and
  this is the measurement it asked Stage 0 to record.

### The Designator Index Today

| | |
| --- | ---: |
| Distinct designator keys | 57,068 |
| Bucketed positions | 138,222 |
| `DesignatorAdjacency.byteSize()` | 3,829,688 bytes (3.65 MiB) |
| Keys that are a `simple_name` | 3,492 |
| Keys that are a `qualified_name` | 93 |
| Keys that are an `expression` | **53,483** |

This is the plan's "a key space, not a vocabulary" claim, measured: 93.7% of the
keys in an index that exists to group claims by name are call sites rather than
names, and the average bucket holds 2.4 positions.

The twenty largest buckets, with how many live definitions in the clone carry
that exact name:

| Positions | Definitions | Shape | Key |
| ---: | ---: | --- | --- |
| 4,389 | 0 | simple_name | `String` |
| 2,668 | 0 | simple_name | `assertEquals` |
| 1,858 | 0 | simple_name | `boolean` |
| 1,318 | 0 | simple_name | `assertThat` |
| 1,091 | 2 | simple_name | `assertTrue` |
| 1,086 | 0 | simple_name | `int` |
| 637 | 0 | simple_name | `when` |
| 606 | 0 | simple_name | `given` |
| 546 | 0 | simple_name | `assertFalse` |
| 524 | 0 | simple_name | `equalTo` |
| 521 | 0 | simple_name | `Object` |
| 438 | 0 | simple_name | `is` |
| 434 | 0 | expression | `builder.build()` |
| 399 | 0 | simple_name | `long` |
| 372 | 0 | expression | `ApplicationModel.defaultModel()` |
| 366 | 3 | simple_name | `mock` |
| 359 | 0 | expression | `e.getMessage()` |
| 354 | 0 | simple_name | `Boolean` |
| 326 | 0 | simple_name | `Integer` |
| 324 | 2 | simple_name | `URL` |

A bucket whose key names no definition in the clone — `String`, `int`, `mock` —
is a claim about something outside the indexed tree. It stays unresolved and
stays unreachable from any anchor in this graph, before this plan and after it.
Only the rows with a definition can ever be reached from a callee anchor.

### Five Definitions, Asked From The Anchor

Selection rule, mechanical and repeatable: **the five largest designator buckets
whose key names at least one live definition in the clone.** Taken from the
`--top 400` report above, they are `assertTrue`, `URL`, `getThis`, `getUrl` and
`verify`.

Measured through the preview, because the preview is what a consumer asks:
`./zig-out/bin/semidx-mcp --root <clone>` driven over stdio with `initialize`,
`notifications/initialized`, then one
`tools/call semidx_references {"name": <name>, "direction": "incoming"}` per
name, all defaults otherwise.

| Name | Definitions | Targets shown | `relationships_total` | Shown | Truncated | Designator bucket |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| `assertTrue` | 2 | 2 | **0** | 0 | no | 1,091 |
| `URL` | 2 | 2 | 93 | 55 | yes, with 3 narrowing hints | 324 |
| `getThis` | 16 | 16 | 23 | 23 | no | 293 |
| `getUrl` | 71 | 50 | 8 | 8 | no, one hint on `targets` | 245 |
| `verify` | 1 | 1 | **0** | 0 | no | 221 |

`unresolved_mentions` does not exist yet, so the right-hand column is unreachable
from these anchors today. That is the gap, stated in the same units the plan
states it in: 1,091 located, explained claims name `assertTrue`, and the two
definitions of `assertTrue` answer with nothing.

### Sampled Claims, And Plan 012's Numbers

`./zig-out/bin/semidx-claim-sample --root <clone> --seed 20260918 --size 1200
--language java`, the protocol Plan 012 used, with the selection rule the
committed harness specifies:

| | Plan 012 Stage 0 | Plan 012 close | Now |
| --- | ---: | ---: | ---: |
| Sampled outgoing claims | 6,710 | 6,710 | 7,283 |
| `defines` facts | — | — | 833 |
| `references` facts / unresolved | 70 / 804 | 70 / 804 | 73 / 831 |
| `calls` facts | 174 | 313 | 265 |
| `calls` unresolved | 5,662 | 5,523 | 5,281 |

**These are not the same 1,200 definitions.** Plan 012's sample was drawn by a
script that was not kept and whose selection rule was never recorded; the
committed harness draws by `sha256(seed + "\n" + key)` rank. The table is a new
baseline beside an old one, not a reproduction of it, which is exactly what
[Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md)
predicted. Two runs of the command produced byte-identical reports.

The same harness over the **whole** Java population (`--size 30000`, which
exceeds the 26,509 definitions and therefore samples all of them) is comparable
to Plan 012's whole-graph table, family by family:

| Family | Plan 012 close (`8a1f083`) | Now (`8025a0c`) | Delta |
| --- | ---: | ---: | ---: |
| `receiver_bound` | 55,127 | 55,127 | 0 |
| `receiver_not_simple_name` | 21,132 | 21,132 | 0 |
| `receiver_reaches_no_class` | 14,171 | 14,110 | −61 |
| `unqualified_no_method` | 13,707 | 13,707 | 0 |
| `enclosing_supertypes` | 6,206 | 6,206 | 0 |
| `unqualified_supertypes` | 4,049 | 4,049 | 0 |
| `unqualified_overloaded` | 1,417 | 1,417 | 0 |
| `target_overloaded` | 887 | 877 | −10 |
| `nested_class_body` | 824 | 824 | 0 |
| `target_supertypes` | 777 | 760 | −17 |
| `target_inaccessible` | 52 | 44 | −8 |
| `on_demand_static_import` | — | 218 | +218 |
| `target_supertypes_unknown`, `target_shape_not_read`, `target_no_method`, `target_not_static`, `target_static_unrecorded` | 0 | 0 | 0 |
| `unclassified` | — | 0 | — |
| **Total unresolved calls** | **118,349** | **118,471** | **+122** |
| Total unresolved references | 19,751 | 19,751 | 0 |

Plan 012's two rows for class bodies declared in a method (629 qualified plus
195 unqualified) are one family here, and 629 + 195 = 824 to the unit.

The `on_demand_static_import` reason did not exist at Plan 012's close:
`git log -S` finds it introduced by `ffb8bf8`, the commit that closed
[Follow-up 016](../followups/016_java_static_call_rule_narrow_gaps.md), and that
is the only commit touching `src/frontends/java.zig` since `8a1f083`. Its 218
claims account for the whole delta exactly:

    218 = 122 (were facts at 8a1f083) + 61 + 17 + 10 + 8 (from four other families)

and the 122 is the same 122 by which current facts fell. Nothing is unexplained,
and no number in this table is a guess.

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the target |
| `zig fmt --check build.zig src tests` | clean |
| `zig build test-core` | passed |
| `zig build designator-shape -Doptimize=ReleaseFast -- --root <clone>` | 3.5 s wall clock including the build step |
| `./zig-out/bin/semidx-claim-sample --root <clone> --seed 20260918 --size 1200 --language java`, twice | byte-identical reports, families sum to the whole, `unclassified` 0 |
| `./zig-out/bin/semidx-claim-sample --root <clone> --seed 20260918 --size 30000 --language java` | 3.5 s, families sum to the whole, `unclassified` 0 |
| `./zig-out/bin/semidx-dev <clone>` | graph totals identical to the designator-shape report |
| `./zig-out/bin/semidx-mcp --root <clone>` over stdio | five `semidx_references` calls answered |

Not run, and why: `zig build test`, `zig build test-mcp`, `zig build dogfood`
and `zig build preview-gate` were not run. Stage 0 changed no indexed behavior —
the only source it added is a developer command outside every lane — and the
plan names `test-core` as this stage's verification. They are Stage 1's bar.

### Residual Risk And Next Step

- **Next step is Stage 1**, unblocked: the Start Rule's stop condition did not
  trigger.
- One of [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md)'s
  required checks was **not** performed: nobody reimplemented the selection rule
  independently and drew the same sample. Both runs here are the same binary, so
  they prove determinism, not that the rule is sufficient to re-derive the
  sample elsewhere. The entry is narrowed rather than closed on that point.
- The five definitions were chosen by a rule, not for how well they show the
  change. Two of them (`assertTrue`, `verify`) have definitions inside the clone
  that are almost certainly not the ones most call sites mean — Dubbo's own
  `Assert.assertTrue` beside JUnit's. That is a feature of the baseline, not a
  flaw in it: after Stage 3 those anchors will return mentions that are **not**
  callers, and D4's rule that a mention is never a relationship is exactly what
  keeps that honest. Stage 4 re-measures the same five.
- The whole-graph family table compares two different classifiers. Every row but
  one matches to the unit and the one that does not is accounted for to the
  claim, but a future comparison should use the committed harness on both sides.
