---
title: "Java receiver coverage through indexed hierarchies progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-21"
---

# 014: Java Receiver Coverage Through Indexed Hierarchies Progress

Companion log for
[docs/plans/014_java_receiver_coverage.md](../plans/014_java_receiver_coverage.md).

## Current Status

**Stage 2 is complete and Gate B passes.** Every declared supertype is now a
recorded `references` claim resolved in the declaring unit's own scope, and a
hierarchy projection walks those claims and reports either the types it reached
or the first condition that stopped it. **4,190 guard-declined claims have a
chain the real graph closes, against a floor of 700** — 86% of Stage 0's
source-derived upper bound, and equal to its strict bound to the unit, so the
model and the implementation agree.

The stage also removed **53 wrong facts** it had no plan to remove: Stage 1
admitted interfaces but left two guards reading two class-only grammar fields,
so a name inside an interface that `extends` another resolved as if nothing
could be inherited. That is recorded below as a defect found and fixed, with
every moved claim counted.

No guard was relaxed. On the fixture corpus, with supertype claims emitted and
no fixture added, all six totals are byte-identical to Stage 1's.

**Stage 1** before it made a top-level Java interface and its methods
definitions the graph holds, under the labels a class carries and with the
implicit modifiers Java defines. On `apache/dubbo` that is **617 declarations
and 2,405 methods** that were a diagnostic and are now findable, outlinable, and
referenceable. [ADR 011](../adr/011_java_hierarchy_from_indexed_source.md)
records the decision.

Nothing the guard declines moved: the two families Gate A is measured on are
still 8,083 and 6,206, every unresolved-call reason family is accounted for
claim by claim, and on the fixture corpus the frontend change alone left
definitions, assertions, facts, unresolved, approximate and diagnostics
identical. The one resolution that moved is the one ADR 011 predicted: **247
reference claims that used to be unresolved now reach an interface.**

Stage 0 before it recorded the baseline and the verdict that authorized this
work: of the 4,738 guard-declined claims whose declared hierarchy is closed in
indexed source, **3,628 (76.6%) reach at least one interface**.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Price both halves on the clone | Completed | Baseline on `apache/dubbo` at `df9c5e1` reproduces Plan 013 Stage 0 to the unit: 230,859 assertions, 92,637 facts, 138,222 unresolved, 118,471 unresolved calls, every reason family identical. Guard families are 8,083 references and 6,206 receivers, exactly as Follow-up 013 records. **Gate A: PASS** — A1 3,628 of 4,738 interface-dependent, A2 4,738 against a floor of 1,000. Gate C input measured early: 2,172 addressable value receivers today, 3,041 with the guard relaxed. |
| Stage 2: A declared supertype is a recorded claim | Completed | D3 shipped, plus `src/frontends/java_hierarchy.zig`: a projection that walks recorded supertype claims and reports a closed chain or the first condition that opened it, used by nothing in the frontend yet. **Gate B: PASS** — 4,190 against a floor of 700, 86% of Gate A's upper bound and equal to its strict bound. On the fixture corpus the frontend change alone is byte-identical; on the clone, references +2,443 and every other claim family unchanged. A Stage 1 defect was found and fixed: 53 wrong facts removed. |
| Stage 1: Interfaces are declarations the graph holds | Completed | D1 and D2 shipped. Interfaces and their methods are definitions with role `interface` and `method`; an unmodified interface method is recorded `public`; the package and class-shape projections carry both roles; the top-level interface diagnostic is gone and the enum, record and annotation type ones stay. On the clone: +3,022 definitions, +1,757 references, +1,411 calls, 247 reference claims converted, and **not one guard-declined claim moved**. [ADR 011](../adr/011_java_hierarchy_from_indexed_source.md). |

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

## Stage 1: Interfaces Are Declarations The Graph Holds

### What Changed

| File | Change |
| --- | --- |
| `src/frontends/java.zig` | `interface_declaration` at the top level becomes a definition with role `interface`; its methods become definitions with role `method`; `modifiersOf` takes the enclosing kind and applies Java's implicit `public`; an interface's constants join the obscuring set; `isTypeRole` names the two roles once for the projections to read; `declaresSupertypes` reads the `extends_interfaces` child a field lookup cannot reach |
| `src/frontends/java_packages.zig` | a package exports both roles, so ADR 004 reaches an interface unchanged |
| `src/frontends/java_members.zig` | `classShapeOf` answers for both roles, so ADR 009 decides a call on an interface by its existing conditions |
| `fixtures/vertical-slice/java/Shape.java` | new: one interface with the three member shapes whose recorded modifiers differ |
| `tests/vertical_slice_test.zig` | five new tests, one re-pinned corpus count, one re-pinned resolution |
| `src/java_coverage.zig` | the measurement command learns assertions by claim kind, the interface-target count, and to walk an interface body |
| `docs/adr/011_java_hierarchy_from_indexed_source.md` | new; `docs/adr/README.md` indexes it |

### The Decision Boundary, Stated

ADR 011 records D1 to D8 and D11. Stage 1 implements **D1 and D2 only**. The
supertype reference (D3), the closedness test (D4 to D6, D8), and the dependency
fan-out (D7) are decided there and implemented in Stages 2 and 3, each behind its
own gate. Nothing in this stage walks a chain or relaxes a guard.

Two boundaries inside D1 and D2 are choices rather than consequences, and are
recorded as such:

- **An interface's constants are collected and not referenced.** They join the
  set of names that obscure a type, because a constant obscures a type of the
  same name inside a `default` or `static` method exactly as a class field does
  (JLS 6.4.2). They keep their `unsupported_construct` diagnostic, and no type
  reference is emitted for them. Emitting one would be new reference coverage
  this plan did not ask for.
- **A member interface is not admitted.** It is not a top-level declaration, it
  keeps the treatment every other member type has, and a test pins that its name
  still declines against the enclosing class as a member type.

### Nothing The Guard Declines Moved

The fixture corpus answers this twice, and the second answer is the one that
matters.

**With the frontend changed and no fixture added**, the corpus totals are
identical to the values ADR 010 pinned: 134 definitions, 465 assertions, 396
facts, 69 unresolved, 0 approximate, 54 diagnostics. Admitting interfaces moved
nothing that was already there, because the corpus declared no interface.

**With `java/Shape.java` added**, the totals are re-pinned, and the delta is one
interface declaring three methods, claim family by claim family:

| Claim | Before | After | Δ | What it is |
| --- | ---: | ---: | ---: | --- |
| `entity_exists` | 164 | 169 | +5 | the file and four definitions |
| `contains` | 29 | 30 | +1 | the repository contains the file |
| `defines` | 134 | 138 | +4 | the unit defines `Shape`, which defines three methods |
| `references` | 21 | 24 | +3 | two `String` return types unresolved, `none`'s own `Shape` a local fact |
| `calls` | 93 | 94 | +1 | `label` calls `describe` |
| `identity_correspondence` | 24 | 28 | +4 | `Greeter.java` is reanalyzed because package `demo` gained an export |
| **total** | **465** | **483** | **+18** | |

Facts 396 → 412, unresolved 69 → 71, approximate 0 → 0, **diagnostics 54 → 54**.
The diagnostic total is the point of the fixture: one interface with three
methods and one constant adds no `unsupported_construct` for the interface
itself.

### On The Clone

Same clone, same commit, same build mode as Stage 0:
`~/.cache/semidx-external/dubbo` at `df9c5e1`, `-Doptimize=ReleaseFast`.

| Measurement | Stage 0 | Stage 1 | Δ |
| --- | ---: | ---: | ---: |
| Definitions | 26,509 | 29,531 | +3,022 |
| Recorded assertions | 230,859 | 243,106 | +12,247 |
| Current facts | 92,637 | 102,350 | +9,713 |
| Current unresolved | 138,222 | 140,756 | +2,534 |
| Approximate | 0 | 0 | 0 |
| Stale | 0 | 0 | 0 |
| Diagnostics | 59,022 | 59,964 | +942 |
| `unsupported_construct` | 58,300 | 59,857 | +1,557 |
| `confirmed_absence` | 722 | 107 | −615 |

The 3,022 new definitions are 617 interfaces and 2,405 of their methods. The 615
units that stop reporting `confirmed_absence` are units whose only declaration
was an interface. Within `unsupported_construct` the only two movements are the
617 top-level interface diagnostics disappearing and the diagnostics for what an
interface body holds besides methods appearing; the net of +1,557 puts the
second at 2,174.

By claim, with Stage 0's column derived from its own recorded totals — the
breakdown print was added during this stage, and the derivation is validated
against Stage 1's measured row:

| Claim | Stage 0 | Stage 1 | Δ |
| --- | ---: | ---: | ---: |
| `entity_exists` | 30,560 | 33,582 | +3,022 |
| `contains` | 4,050 | 4,050 | 0 |
| `defines` | 26,509 | 29,531 | +3,022 |
| `references` | 21,491 | 23,248 | +1,757 |
| `calls` | 123,499 | 124,910 | +1,411 |
| `identity_correspondence` | 24,750 | 27,785 | +3,035 |

### Every Move, Counted

**References.** 366 reference facts now reach an interface. 119 of them are made
by an interface or one of its methods, so they are new claims by new entities.
The other **247 are the move**: claims that existed before this stage, were
unresolved, and now resolve. That is the coverage ADR 011 predicted and the
Plan 014 branch handling requires counted, and
`tests/vertical_slice_test.zig` pins one example — a field whose type names an
interface the same unit declares, which used to decline as "a non-class type of
this name" and is now a local fact, beside an `enum` of the same shape that
still declines.

The whole reference delta closes on those numbers: 1,757 new reference claims
from interface method return types, of which 219 are facts and 1,538 unresolved;
plus the 247 conversions. Facts +219 +247 = +466, which is 1,740 → 2,206.
Unresolved +1,538 −247 = +1,291, which is 19,751 → 21,042.

**Calls.** Every unresolved-call reason family, from
`zig build claim-sample -Doptimize=ReleaseFast -- --root <clone> --seed 20260918
--size 40000 --language java`, a census over all definitions with `unclassified`
at zero on both sides:

| Family | Stage 0 | Stage 1 | Δ |
| --- | ---: | ---: | ---: |
| `receiver_not_simple_name` | 21,132 | 21,444 | +312 |
| `nested_class_body` | 824 | 829 | +5 |
| `receiver_bound` | 55,127 | 55,565 | +438 |
| `on_demand_static_import` | 218 | 218 | 0 |
| **`enclosing_supertypes`** | **6,206** | **6,206** | **0** |
| `receiver_reaches_no_class` | 14,110 | 14,148 | +38 |
| `target_supertypes` | 760 | 780 | +20 |
| `target_overloaded` | 877 | 879 | +2 |
| `target_inaccessible` | 44 | 44 | 0 |
| `unqualified_no_method` | 13,707 | 13,888 | +181 |
| `unqualified_overloaded` | 1,417 | 1,631 | +214 |
| `unqualified_supertypes` | 4,049 | 4,082 | +33 |
| the five families that are zero | 0 | 0 | 0 |
| **total** | **118,471** | **119,714** | **+1,243** |

Every delta is an addition, not a movement: +1,243 unresolved and +168 fact
calls make the +1,411 the claim table records, and all of them are invocations
inside `default` and `static` interface method bodies that no analysis read
before. **`enclosing_supertypes` is unchanged at 6,206**, which is the family
Gate A is measured on and the family Stage 3 exists to convert.

The guard families in the coverage command agree: 8,083 references and 6,206
receivers, identical to Stage 0. Gate A re-measures to the same 4,738 and 3,628,
because the hierarchy is read from source and does not depend on what the graph
holds.

### The Measurement Command Reported Its Own Gap

The first Stage 1 run of `semidx-java-coverage` reported **438 value-receiver
claims it could not locate**, where Stage 0 reported none. They were the
invocations inside interface method bodies: the classifier walked top-level
classes only. The row exists so that a miss is loud rather than silent, and it
did its job on the first stage that could produce one. The walk now covers both
declarations and collects an interface's constants, and all 55,565 claims are
located again.

### One Concern With The Plan As Written, Stated And Followed

Plan 014's Non-Scope says `resolveType`'s existing explanations keep their
current wording. Several of them now say "class" where the rule they describe
considers a class **or an interface** — for example "no current top-level class
of this name is declared in package `demo`", which is emitted when the package
declares neither. The conditions are unchanged and no claim moved, so this is
wording rather than behavior, and it is left exactly as the plan requires. It is
recorded here so Stage 6's drift control decides it deliberately rather than
inheriting it. The invocation-path declines were not reworded either, for the
same reason.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core` | pass |
| `zig build test` | pass, 99 tests in the vertical slice lane (was 94) |
| `zig build test-mcp` | pass, 35/36 with 1 skipped |
| `zig build dogfood` | pass, 10/10 steps, 5/5 tests |
| `zig fmt --check build.zig src tests` | clean |
| `zig build java-coverage -Doptimize=ReleaseFast -- --root <clone>` | the tables above |
| `zig build claim-sample -Doptimize=ReleaseFast -- --root <clone> --seed 20260918 --size 40000 --language java` | families sum to the whole, `unclassified` 0 |

`zig build preview-gate` was not run: Stage 1's verification list does not name
it, and no query shape, budget, or work bound changed. Stage 3 runs it.

### Residual Risk

- **An interface's constants have no type reference.** A name written only as a
  constant's type is invisible to the graph. It is a recorded coverage boundary,
  not a defect, and the member carries its own `unsupported_construct`.
- **The 2,174 new member diagnostics are derived, not itemized.** They follow
  from the net `unsupported_construct` delta and the 617 that disappeared. No
  count of interface bodies' members was taken directly.
- **`identity_correspondence` grew by 3,035, more than the 3,022 new
  definitions.** Reanalysis within a batch re-emits correspondence for entities
  that already existed, which is the same channel
  [Follow-up 018](../followups/018_unexplained_assertion_delta.md) points at;
  frontend reads on the clone went from 7,291 to 7,665. Nothing here is
  unaccounted, but Stage 4 must read its assertion delta against this number
  rather than against Stage 0's.

### Next Stage

Stage 2 makes each declared supertype a recorded `references` claim resolved in
the declaring unit's scope, adds the hierarchy projection beside
`java_members.zig`, and measures Gate B: guard-declined claims whose chain is
closed in the real graph, against a floor of 700. Stage 0's source-derived upper
bound for that number is 4,738 lenient and 4,113 strict, so Gate B has room —
but the graph's answer is what counts, and a fail ends the sequence at Stage 2.

## Stage 2: A Declared Supertype Is A Recorded Claim

### What Changed

| File | Change |
| --- | --- |
| `src/core/graph.zig` | `currentRelationshipsFrom`: the companion of `currentDefinitionFact`, bounded the same way. A read over assertions that already exist — no kind, no index, no stored state |
| `src/frontends/java.zig` | every declared supertype emits a `references` claim from the declaring type, resolved by the unchanged `resolveType` in a `supertype` position; `supertype_claim.prefix` marks those claims; `member_types` records what a type declares so a later walk can ask; both guards now read the enclosing type's recorded shape instead of two class-only grammar fields |
| `src/frontends/java_hierarchy.zig` | new projection: direct supertypes, the closure, and two rule-out questions. It resolves nothing and names no target |
| `src/frontends/root.zig` | exports it |
| `fixtures/vertical-slice/java/Circle.java` | new: a class implementing an interface its own unit declares, so the corpus carries a closed chain |
| `tests/vertical_slice_test.zig` | three new tests, one re-pinned corpus count |
| `src/java_coverage.zig` | walks the graph hierarchy for Gate B, and splits references by position |

### How A Supertype Claim Says It Is One

A declared supertype and a field's type are both `references` claims out of the
same entity, and a relationship carries no extension payload. So the claim says
which position it was read in the only place it can: the Java frontend writes
`supertype_claim.prefix` in front of `resolveType`'s own words, on the resolved
and the unresolved path alike, and `java_hierarchy` reads it back. Both ends
name one constant, so the two cannot drift apart.

`resolveType`'s words are kept verbatim behind the prefix, which is what
Stage 2 needs: an unresolved supertype still says exactly why, so an open chain
is visible as a name that reached nothing rather than as an absence. It is the
same shape `qualifiedTarget` already used for "the receiver is not read as a
class: …".

### The Position Decides One Thing

`resolveType` gained a position, and it decides exactly one condition: whether
the enclosing type's **own** supertypes may give the name another meaning.

Inside the body they may — a member type could be inherited. In an `extends` or
`implements` clause they may not: the scope of a member declared in or inherited
by a type is the *body* of that type (JLS 6.3), and the header is not the body.
A type cannot inherit a name before it has said what it inherits from. Without
that distinction a supertype of any type that declares supertypes would decline
by the guard it is evidence for, every chain would be open, and Gate B would
read zero by construction rather than by measurement.

Everything else `resolveType` asks is unchanged and still asked, including the
conservative one: a member type of the name declared in the type's own body
still declines a supertype of that name. Strictly the header is outside that
scope too, but declining leaves the chain open, which is the safe direction.

### A Stage 1 Defect, Found And Fixed

Stage 1 admitted interfaces as declarations but left two guards reading
`superclass` and `interfaces` directly off the grammar. An interface writes its
supertypes in an `extends_interfaces` child, which carries no field name, so
both guards saw an interface that `extends` another as having no supertypes and
let names resolve as if nothing could be inherited. Both now read the enclosing
type's recorded shape, which is the same value the `java.supertypes` label
carries.

It is a correctness fix in the direction §3 requires, and every claim it moved
is counted. On the clone:

| | Before | After | Moved |
| --- | ---: | ---: | ---: |
| References in a non-supertype position, facts | 2,206 | 2,154 | **−52** |
| Same, unresolved | 21,042 | 21,094 | +52 |
| Same, total | 23,248 | 23,248 | 0 |
| `calls` facts | 5,196 | 5,195 | **−1** |
| `enclosing_supertypes` (the receiver guard) | 6,206 | 6,240 | +34 |
| `receiver_reaches_no_class` | 14,148 | 14,117 | −31 |
| `target_supertypes` | 780 | 778 | −2 |
| Guard's reference family | 8,083 | 8,294 | +211 |

**53 assertions changed category from fact to unresolved, and nothing changed
the other way.** Each was a name resolved inside an interface that extends
another. The 34 that entered the receiver guard's family decompose exactly: 1
was a fact, 31 declined for another receiver reason, 2 for a target reason. Of
the 211 that entered the reference guard's family, 52 were facts and 159
declined for another reason.

### The Fixture Corpus

**With supertype claims emitted and no fixture added**, the corpus totals are
byte-identical to Stage 1's: 138 definitions, 483 assertions, 412 facts, 71
unresolved, 0 approximate, 54 diagnostics. That is what "no guard changes in
this stage" had to mean and what it was proven to mean.

`java/Circle.java` then adds a class implementing an interface its own unit
declares, so the corpus carries a closed hierarchy that whatever indexes the
fixtures exercises:

| Claim | Before | After | Δ |
| --- | ---: | ---: | ---: |
| `entity_exists` | 169 | 174 | +5 |
| `contains` | 30 | 31 | +1 |
| `defines` | 138 | 142 | +4 |
| `references` | 24 | 27 | +3 |
| `calls` | 94 | 94 | 0 |
| `identity_correspondence` | 28 | 32 | +4 |
| **total** | **483** | **500** | **+17** |

Facts 412 → 427, unresolved 71 → 73, **diagnostics 54 → 54**. Of the three new
references, the supertype is a local fact and the two `String` return types are
unresolved.

The vertical-slice fixture paths do not spell their declared package, so under
[ADR 008](../adr/008_java_visibility_boundaries.md) they resolve nothing across
units. That is why the corpus hierarchy is declared inside one unit: a
cross-unit supertype there would be unresolved for a reason that has nothing to
do with this stage.

### On The Clone

| Measurement | Stage 1 | Stage 2 | Δ |
| --- | ---: | ---: | ---: |
| Definitions | 29,531 | 29,531 | 0 |
| Recorded assertions | 243,106 | 245,549 | +2,443 |
| Current facts | 102,350 | 103,402 | +1,052 |
| Current unresolved | 140,756 | 142,147 | +1,391 |
| Diagnostics | 59,964 | 59,964 | 0 |
| `entity_exists` / `contains` / `defines` / `calls` | — | — | **0** |
| `references` | 23,248 | 25,691 | **+2,443** |

**Exactly one claim family moved.** The 2,443 new claims are every supertype a
class or an interface declares — the source model counts 2,448 declared links,
and the five it counts that are not emitted belong to `enum` declarations, which
are not definitions and so make no claims.

By position:

| | fact | unresolved |
| --- | ---: | ---: |
| Declared supertype | 1,105 | 1,338 |
| Every other position | 2,154 | 21,094 |

1,105 + 1,338 = 2,443, and 2,154 + 21,094 = 23,248, which is Stage 1's whole
reference total. No reference claim appeared or disappeared outside the
supertype position; 52 changed category, and that is the defect above.

Reference facts reaching an interface went 366 → 1,048.

### Gate B

Measured over the real graph with `java_hierarchy.closureOf`, over the reference
and receiver families as D12 defines it:

| | reference | receiver | unqualified |
| --- | ---: | ---: | ---: |
| Enclosing type not in the graph | 0 | 0 | 0 |
| **Chain closed** | **2,247** | **1,943** | 951 |
| `supertype_unresolved` | 6,047 | 4,297 | 3,131 |
| `supertype_not_a_type` | 0 | 0 | 0 |
| `supertype_provider_stale` | 0 | 0 | 0 |
| `cycle` | 0 | 0 | 0 |
| `depth_cap` | 0 | 0 | 0 |

| Test | Number | Floor | Verdict |
| --- | ---: | ---: | --- |
| **B** — guard-declined claims whose chain is closed in indexed source | **4,190** | 700 | **PASS** |

4,190 is 86% of Gate A's source-derived upper bound of 4,823, and it equals
Gate A's **strict** bound of 4,190 to the unit. That is the strongest evidence
this plan has produced: Stage 0's strict bound modelled exactly what an
unchanged `resolveType` answers about a supertype's written shape, and the
implementation reproduced it without either being fitted to the other.

The gap to the lenient bound is 633 claims, and it is entirely the shape rule: a
supertype written as `Foo<T>` or `a.b.C` declines, so its chain is open. Nothing
on this clone hits a cycle, a depth cap, a stale provider, or a non-type
supertype.

Gate A re-measures to 4,823 rather than Stage 0's 4,738 because the guard fix
put 245 more claims in the families it is measured over; the walk itself is
unchanged.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core` | pass |
| `zig build test` | pass, 276/278 with 2 skipped; 102 tests in the vertical-slice lane (was 99) |
| `zig build test-mcp` | pass, 35/36 with 1 skipped |
| `zig build dogfood` | pass, 10/10 steps, 5/5 tests |
| `zig fmt --check build.zig src tests` | clean |
| `zig build java-coverage -Doptimize=ReleaseFast -- --root <clone>` | the tables above |
| `zig build claim-sample … --size 40000` | families sum to the whole, `unclassified` 0 |

### Residual Risk

- **A supertype claim is identified by a prefix on its own resolution words.**
  It is the only channel a relationship has, both ends name one constant, and a
  test would fail loudly if they drifted — but it is a string, and a core that
  someday gives relationships an extension payload should take it over.
- **633 closable claims are lost to the type shape rule.** A supertype written
  generically or qualified leaves its chain open. Follow-up 014 already prices
  the receiver-side version of that relaxation; the supertype-side version is a
  new finding this plan has not priced.
- **The 5 unemitted enum supertype links are accounted for but not pinned.** No
  test asserts that an enum's `implements` makes no claim.

### Next Stage

Stage 3 wires the projection into the frontend: the guard lifts only where the
chain is closed and nothing reachable declares the name, on the reference and
the receiver side, with a distinct reason for every failure and a reader hinted
for every type its walk visited.
