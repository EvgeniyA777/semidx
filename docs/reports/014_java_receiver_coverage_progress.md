---
title: "Java receiver coverage through indexed hierarchies progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-20"
---

# 014: Java Receiver Coverage Through Indexed Hierarchies Progress

Companion log for
[docs/plans/014_java_receiver_coverage.md](../plans/014_java_receiver_coverage.md).

## Current Status

**Stage 0 is complete and Gate A passes on both tests.** The plan's Start Rule
asks one question before the stage order may stand: is the guard's closable
opportunity dominated by interfaces? **It is.** Of the 4,738 guard-declined
claims whose declared hierarchy is closed in indexed source, **3,628 (76.6%)
reach at least one interface**, so more than three quarters of the opportunity
disappears if interfaces stay diagnostics. Stages 1 to 4 are authorized.

The stage added one developer-only measurement command and changed no indexed
behavior: no frontend, no core, no MCP surface, and no lane was touched.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Price both halves on the clone | Completed | Baseline on `apache/dubbo` at `df9c5e1` reproduces Plan 013 Stage 0 to the unit: 230,859 assertions, 92,637 facts, 138,222 unresolved, 118,471 unresolved calls, every reason family identical. Guard families are 8,083 references and 6,206 receivers, exactly as Follow-up 013 records. **Gate A: PASS** — A1 3,628 of 4,738 interface-dependent, A2 4,738 against a floor of 1,000. Gate C input measured early: 2,172 addressable value receivers today, 3,041 with the guard relaxed. |

## Stage 0: Price Both Halves On The Clone

### Environment

| | |
| --- | --- |
| Repository commit at stage start | `1b52fb9`, branch `dev`, clean worktree |
| Zig | 0.16.0 (`./scripts/check-zig-version.sh` passes) |
| Measured clone | `~/.cache/semidx-external/dubbo`, outside this repository |
| Clone commit | `df9c5e13bc014ef492ec20824f8623a5e092a5b1` (`df9c5e1`) |
| Clone worktree | clean, 0 modified or untracked files |
| Build mode | `-Doptimize=ReleaseFast` |

The clone is evidence, not a conformance target: no lane, hook, or `.mcp.json`
entry names it, and no test asserts against a number taken from it.

### The Baseline Reproduces

`zig build java-coverage -Doptimize=ReleaseFast -- --root <clone>`, and
`zig build claim-sample -Doptimize=ReleaseFast -- --root <clone> --seed 20260918
--size 30000 --language java`:

| Measurement | This stage | [Plan 013 Stage 0](013_unresolved_mentions_from_the_callee_anchor_progress.md#stage-0-reproducible-baseline) |
| --- | ---: | ---: |
| Source units indexed | 4,050 | 4,050 |
| Java definitions | 26,509 | 26,509 |
| Recorded assertions | 230,859 | 230,859 |
| Current facts | 92,637 | 92,637 |
| Current unresolved | 138,222 | 138,222 |
| Approximate | 0 | 0 |
| Stale | 0 | 0 |
| Diagnostics | 59,022 | 59,022 |
| Unresolved `calls` | 118,471 | 118,471 |
| Unresolved `references` | 19,751 | 19,751 |

Diagnostics split 58,300 `unsupported_construct` and 722 `confirmed_absence`,
with no `analysis_failed` and no `analysis_unavailable`.

Every unresolved-call reason family `claim_sample` names is identical to Plan 013
Stage 0's column, to the unit, and the families sum to the whole with
`unclassified` at zero. The three families relevant here:

| Family | Count |
| --- | ---: |
| `receiver_bound` | 55,127 |
| `enclosing_supertypes` (receiver side of the guard) | 6,206 |
| `unqualified_supertypes` (unqualified side of the guard) | 4,049 |

The reference side of the guard is 8,083 of the 19,751 unresolved references.
Both guard figures are exactly what
[Follow-up 013](../followups/013_java_supertype_guard_relaxation.md) records, and
55,127 is exactly what
[Follow-up 014](../followups/014_java_instance_receiver_calls.md) records, so the
classification below is anchored on the families those entries priced and not on
a re-derivation of them.

Two runs of the command produced byte-identical reports.

### Follow-up 018 On This Clone

[Follow-up 018](../followups/018_unexplained_assertion_delta.md) records 106
assertion records that appeared with no accounted cause between `384507e` and
`8a1f083`.

What reproduces here, at `1b52fb9`: the recorded-assertion total is **230,859**,
which is the same number on the "after" side of that entry's table and the same
number Plan 013 Stage 0 recorded at `8025a0c`. Three commits that changed the
designator and the static-call rule have since left it untouched, so the figure
any Stage 4 delta will be compared against is stable and is recorded here.

What does **not** reproduce here: the before/after probe that produced the 106.
Re-running it means building the pre-Plan-012 commit, whose write path and
designator are not the ones this plan changes, so it would measure a different
program rather than re-take this one's number. It is not run, and that is stated
rather than implied.

What this stage did add is the mechanism's size on this clone. One scan of the
4,050 units costs **7,291 frontend reads, 3,241 of them invalidations**: four
units in five are read a second time inside one batch. That is exactly the
batch-wide reanalysis Follow-up 018 names as the unfollowed lead, now measured,
and it is why a Stage 4 assertion-count delta must be checked against this
number rather than attributed to this plan's changes.

### The Source Model Of The Declared Hierarchy

The hierarchy is not in the graph, so it is read from source with the same
tree-sitter Java grammar the frontend uses. Top-level type declarations on the
clone:

| Kind | Count |
| --- | ---: |
| class | 3,337 |
| interface | 617 |
| enum | 57 |
| annotation type | 45 |
| record | 0 |
| **declaring at least one supertype** | **2,139** |

Those 2,139 types write **2,448 supertype links**, 1,647 of them in an
`implements` or `extends`-interfaces position. By how the link is written:
1,926 a bare simple name, 368 generic (`Foo<T>`), 144 qualified (`a.b.C`), 10
neither.

Where one link reaches, resolved from the declaring unit under ADR 004 and
ADR 008:

| | Count |
| --- | ---: |
| An indexed top-level declaration | 1,398 (856 of them an interface) |
| Out of the declaring unit's visibility scope | 522 |
| Nothing indexed declares the name | 528 |
| Ambiguous | 0 |

**Over 61% of the links that resolve at all resolve to an interface.** That is
the single-link version of the finding the plan is built on, before any chain is
walked.

### The Guard Family, Classified From Source

Every unresolved claim the guard declined, by the frontend's own words, with its
enclosing type's chain walked depth-first under a visited path and a depth cap
of 16:

| | reference | receiver | unqualified |
| --- | ---: | ---: | ---: |
| Total | 8,083 | 6,206 | 4,049 |
| Enclosing type not found in the model | 0 | 0 | 0 |
| Enclosing type declares no supertype | 0 | 0 | 0 |
| **Chain closed (lenient)** | **2,566** | **2,172** | 1,293 |
| of those, reaching an interface | 1,963 | 1,665 | 866 |
| Chain closed (strict) | 2,173 | 1,940 | 948 |
| of those, reaching an interface | 1,833 | 1,466 | 759 |

Every claim found its enclosing type and every enclosing type declared a
supertype, which is the check that the classification is looking at the claims
the guard actually declined.

Two bounds are reported because they answer two questions. The **lenient** bound
follows the base name of a generic supertype, and it is the upper bound Gate A
is measured on: it checks neither member types, nor access, nor staleness, nor
the real resolution of each name, exactly as the plan requires it to be
labelled. The **strict** bound leaves a chain open at any supertype that is not
a bare `type_identifier`, which is what today's unchanged `resolveType` answers;
it is recorded so Stage 4's realized count has something honest to be compared
against on both sides.

Why a chain stayed open, lenient / strict:

| First condition that failed | reference | receiver | unqualified |
| --- | ---: | ---: | ---: |
| Supertype name reaches nothing indexed | 2,897 / 2,387 | 1,397 / 1,209 | 1,028 / 849 |
| Supertype outside the visibility scope | 2,319 / 1,813 | 2,418 / 1,588 | 1,567 / 998 |
| Supertype not written as a simple name | 301 / 1,710 | 219 / 1,469 | 161 / 1,254 |
| Ambiguous supertype | 0 / 0 | 0 / 0 | 0 / 0 |
| Supertype is not a class or interface | 0 / 0 | 0 / 0 | 0 / 0 |
| Cycle | 0 / 0 | 0 / 0 | 0 / 0 |
| Depth cap | 0 / 0 | 0 / 0 | 0 / 0 |

Not one chain on this clone hits the depth cap and not one declares a cycle. The
two dominant blockers are a supertype nothing indexed declares — a JDK or
dependency type — and a supertype in another Maven module, which ADR 008 keeps
out of scope. Both are honest limits of an indexed working copy rather than
limits of the walk.

### Gate A

The gate is measured over references plus call receivers, as D12 defines it. The
unqualified family is recorded above but is not part of the arithmetic.

| Test | Number | Floor | Verdict |
| --- | ---: | ---: | --- |
| **A1** — at least half of the guard family's closable opportunity depends on interfaces | 3,628 of 4,738 (76.6%) | 50% | **PASS** |
| **A2** — the closed-hierarchy upper bound is at least 1,000 whole-graph claims | **4,738** | 1,000 | **PASS** |

Both pass, and A1 passes by a wide margin: the plan predicted from Plan 012's
sample that a pre-interface subset would reach about 554, and the measured
subset that needs no interface is 1,110. Without D1 this plan would clear
neither floor. The strict bound is 4,113, so even under today's unchanged type
shape rule the opportunity is four times A2's floor.

**Stages 1 to 4 are executed.** The Start Rule's condition for re-opening the
plan — that the opportunity is not dominated by interfaces — did not occur.

### The Fan-Out Under D7

Over the 14,289 reference and receiver claims, walking each enclosing type's
chain:

| Chain depth reached | Claims |
| ---: | ---: |
| 0 | 5,960 |
| 1 | 5,457 |
| 2 | 1,838 |
| 3 | 684 |
| 4 | 350 |

| Distinct types one walk visits | Claims |
| ---: | ---: |
| 1 | 5,960 |
| 2 | 5,262 |
| 3 | 1,854 |
| 4 | 627 |
| 5 | 516 |
| 6 | 51 |
| 7 | 19 |

A depth of 0 is a chain that failed at its first link; the walk visits the
starting type and stops. **No walk reaches depth 5 and none visits more than
seven types.**

2,082 distinct types were visited by at least one walk. The fan-out D7 asks
about is how many distinct reader units one type would owe a reanalysis, and the
worst case on this clone is **33**:

| Reader units | Type |
| ---: | --- |
| 33 | interface `Prioritized` (`dubbo-common/.../common/lang/Prioritized.java`) |
| 25 | class `Node` (`dubbo-plugin/dubbo-rest-openapi/.../openapi/model/Node.java`) |
| 21 | interface `ChannelHandler` (`dubbo-remoting/dubbo-remoting-api/.../remoting/ChannelHandler.java`) |
| 20 | class `AbstractConfig` (`dubbo-common/.../config/AbstractConfig.java`) |
| 20 | interface `BaseFilter` (`dubbo-rpc/dubbo-rpc-api/.../rpc/BaseFilter.java`) |
| 19 | interface `Filter` (`dubbo-rpc/dubbo-rpc-api/.../rpc/Filter.java`) |
| 18 | interface `Merger` (`dubbo-cluster/.../rpc/cluster/Merger.java`) |
| 18 | interface `StateRouter` (`dubbo-cluster/.../router/state/StateRouter.java`) |
| 17 | class `AbstractStateRouter` (`dubbo-cluster/.../router/state/AbstractStateRouter.java`) |
| 17 | class `AbstractBuilder` (`dubbo-config/dubbo-config-api/.../bootstrap/builders/AbstractBuilder.java`) |

This is the input, not the acceptance: the number counts readers with a
guard-declined claim, and D7 would hint every reader that walked the chain,
including those whose walk closed. It is recorded so Stage 3 has something to
measure its real hint set against.

### The Value-Receiver Family, Classified From Source

All 55,127 claims were located in the parse tree by the start byte of their own
evidence; none was unplaceable, and the classification sums to the whole in both
columns. "Today" is the graph as it stands; "relaxed" differs in exactly one
condition — whether the enclosing class's declared supertypes stop the receiver
type from resolving.

| Where the call stops | Today | Relaxed |
| --- | ---: | ---: |
| **addressable under D10** | **2,172** | **3,041** |
| Binding introducer not covered | 3,279 | 3,279 |
| Declared type shape not covered (generic, array, `var`) | 14,769 | 14,769 |
| Declared type is a type parameter | 130 | 130 |
| Declared type is a member type of the enclosing class | 1,224 | 1,224 |
| Blocked by the enclosing class's supertypes | 3,345 | 0 |
| Receiver type reaches nothing indexed | 11,356 | 11,356 |
| Receiver type out of the visibility scope | 11,235 | 11,235 |
| Receiver type is not a class or interface | 66 | 99 |
| Receiver type is an interface, every other condition met | 610 | 1,097 |
| Target's own chain is open | 4,952 | 6,213 |
| The invoked name is declared in the target's chain | 1,318 | 1,815 |
| Target declares no method of the name | 52 | 67 |
| Target declares overloads of the name | 418 | 571 |
| Target's method is outside the resolvable access | 201 | 231 |
| Receiver name not bound where the call is | 0 | 0 |
| Inside a class body declared in the method | 0 | 0 |
| **Sum** | **55,127** | **55,127** |

Three things in that table are worth naming rather than leaving in a row.

- **The dominant blocker is not the guard.** 14,769 receivers declare a type
  shape Plan 012's covered list does not admit, and 22,591 more declare a type
  no indexed unit in scope declares. Together that is 68% of the family, and
  none of it moves when the guard lifts.
- **610 calls are one Stage away from a fact.** They satisfy every condition D10
  lists and are blocked only because their receiver type is an interface, which
  is not a definition today. Stage 1 alone converts that subset, and the relaxed
  column says the number rises to 1,097 once the guard lifts as well.
- **The chain rules out, and it costs something.** 1,318 calls have a target
  whose chain is closed but which inherits the invoked name somewhere in it.
  D6 keeps every one of them unresolved, and that is the right answer; the row
  exists so that the cost of the rule is visible rather than hidden inside a
  larger decline.

### Gate C, Measured Early

Gate C is the plan's Stage 4 measurement and is formally taken on the graph
after Stage 3. This stage measures its input on today's graph so the
value-receiver half is priced before four stages of work, as the plan's branch
handling requires a failing Gate A to do:

| Condition | Value-receiver calls addressable under D10 | Floor |
| --- | ---: | ---: |
| Today's graph | 2,172 | 1,000 |
| With the supertype guard relaxed | 3,041 | 1,000 |

Both are above the floor, and neither is the Stage 4 verdict. Stage 1 and
Stage 3 both move the number: interfaces as definitions add the 610 to 1,097
interface-typed receivers, and a closed-chain test may convert part of the 4,952
open-chain targets. The forecast for Stage 4 is therefore the relaxed figure
plus the interface row, roughly 4,100, against Plan 012's sample-scaled
prediction of about 1,390.

### The Procedure

The procedure is written out in full in the header of
[`src/java_coverage.zig`](../../src/java_coverage.zig) and is repeated in
outline here, because a procedure that lives only in one implementation is the
defect [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md)
records. It needs no seed: every count above is a census, not a sample.

1. Index the root, publish one snapshot, report its totals.
2. Parse every Java unit and record, per unit, its declared package, its Java
   source root, its single-type imports, and every top-level type declaration —
   name, kind, the methods it declares with access and `static`, the member
   types it declares, and its supertype links read down to a base name and a
   shape.
3. Resolve a simple name from a referring unit as ADR 004 and ADR 008 permit:
   the unit's own declarations, then a single-type import whose answer is final
   either way, then the unit's explicit package, and only across source roots
   that share scope.
4. Walk the hierarchy depth-first with a path stack and a depth cap of 16. A
   chain is closed when every supertype on every reachable type resolves by
   step 3 to a top-level class or interface.
5. Take each guard-declined claim by matching the frontend's own explanation,
   find its enclosing type through the claim's source entity, and walk that
   type's chain.
6. Take each value-receiver claim the same way, read the receiver name from the
   backticks in its explanation and the invoked name from its designator,
   locate the invocation by the start byte of its evidence, and ask D10's
   conditions in order, twice.
7. Report the depth and visit distributions and the largest reader set.

Matching the frontend's own words is deliberate: rewording a reason in
`src/frontends/java.zig` makes its claims vanish from a row here, which is
visible, rather than moving them somewhere plausible, which is not.

### The Classifier Was Checked Before It Was Believed

A Java tree was written so that every branch of the classification is reached,
and the counts were verified by hand against it before the clone was measured:

| Branch | Proven by |
| --- | --- |
| Closed chain through a class and an interface | `Leaf extends Mid`, `Mid extends Base implements Marker` |
| Qualified supertype | `extends java.util.ArrayList` |
| Supertype nothing declares | `extends NotIndexedAnywhere` |
| Generic supertype: closed lenient, open strict | `extends Box<String>` |
| Supertype that is not a class or interface | `extends Color`, an enum |
| Cycle | `CycleA extends CycleB`, `CycleB extends CycleA` |
| Depth cap | a chain of eighteen classes |
| Every value-receiver stop | one method per stop in one class |

Hand-checked totals: 24 guard-declined references, 1 receiver, 1 unqualified;
17 chains closed lenient and 16 strict; 11 value-receiver calls summing across
their stops. Each matched the program.

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig version 0.16.0 matches semidx target |
| `zig build test-core` | pass |
| `zig fmt --check build.zig src tests` | clean |
| `zig build java-coverage -- --root fixtures` | runs; the fixture corpus declares no supertype, so every guard row is zero |
| `zig build java-coverage -- --root <controlled tree>` | every branch reached, counts hand-checked |
| `zig build java-coverage -Doptimize=ReleaseFast -- --root <clone>`, twice | byte-identical reports, 36 s wall clock including the build |
| `zig build claim-sample -Doptimize=ReleaseFast -- --root <clone> --seed 20260918 --size 30000 --language java` | families sum to the whole, `unclassified` 0, every family identical to Plan 013 Stage 0 |

`zig build test`, `test-mcp`, `dogfood` and `preview-gate` were not run: this
stage changed no indexed behavior, and the only code it added is a developer
tool no lane builds. Stage 1 runs the full set.

### What This Stage Changed

| File | Change |
| --- | --- |
| `src/java_coverage.zig` | new developer-only measurement command |
| `build.zig` | a `java-coverage` step, on the same terms as `claim-sample` and `designator-shape`: no lane, hook, or `.mcp.json` entry depends on it |
| `docs/reports/014_java_receiver_coverage_progress.md` | this log |

`MEMORY.md` is deliberately not updated: the plan's drift control assigns it to
Stage 6, and it is a bounded file that should not spend lines on a plan that
could still stop at a gate.

### Residual Risk

- **The upper bound is an upper bound.** It checks no member type, no access, no
  staleness, and not the real resolution of each supertype name. Stage 4 must
  compare the realized count against 4,738 and explain the gap by naming the
  conditions that consumed it, not smooth it over.
- **The value-receiver classification is a model, not an implementation.** No
  code resolves a value receiver today, so its 2,172 and 3,041 are what the
  rules predict rather than what a frontend produced. The guard family's
  totals are not a model: 8,083 and 6,206 come from the graph and match
  Follow-up 013 to the unit.
- **The fan-out figure counts only readers with a guard-declined claim.** The
  real D7 hint set is larger, and Stage 3 measures it.
