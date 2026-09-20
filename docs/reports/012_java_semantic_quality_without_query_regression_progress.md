---
title: "Java semantic quality without query regression progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-20"
---

# 012: Java Semantic Quality Without Query Regression Progress

Companion log for
[docs/plans/012_java_semantic_quality_without_query_regression.md](../plans/012_java_semantic_quality_without_query_regression.md).

## Current Status

**The plan is complete.** Java invocations written `ClassName.method(...)`
resolve to the one `static` method that class declares, under every
[ADR 009](../adr/009_java_static_calls.md) condition at once, and everything
else stays unresolved saying which condition failed.

Measured on the external sample this plan has used throughout — apache/dubbo at
`df9c5e1`, the same 1,200 definitions, the same 6,710 outgoing claims:

| | Stage 0 | Now |
| --- | ---: | ---: |
| `calls` facts | 174 | **313** |
| Of those, static-call facts | 0 | **139** |
| `calls` unresolved | 5,662 | 5,523 |
| `references` facts / unresolved | 70 / 804 | 70 / 804 |
| Peak RSS, ReleaseFast | 186 MB | 185 MB |
| `semidx_context depth=2` | 0.019 s | 0.005 s |

139 against a required floor of 100 and a Stage 0 prediction of 135. The one
Stage 0 reason for 4,624 receiver-qualified calls decomposes exactly into seven
named families plus those 139 facts.

The plan was **amended once**, after its own Stage 0 gate declined the original
subject at 63 addressable invocations against a required 100. See
[Amendment 1](../plans/012_java_semantic_quality_without_query_regression.md#amendment-1-from-instance-receivers-to-static-calls)
and [The Decision](#the-decision).

Stage 0 also settled the question Plan 011 deliberately left open: the external
latency observation now exists, and it supports the Plan 011 product claim
strongly. `semidx_context depth=2` on apache/dubbo fell from **90.71 s to
0.019 s** in the same build mode on the same repository and commit.

The plan was reviewed after closure. Nothing reopened it; three findings were
deferred to Follow-ups [015](../followups/015_unit_path_change_does_not_reanalyze.md),
[016](../followups/016_java_static_call_rule_narrow_gaps.md) and
[017](../followups/017_plan_012_external_evidence_reproducibility.md), and the
rest are recorded in
[Post-Closure Review](#post-closure-review-2026-09-20).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Post-Plan-011 external baseline and addressability gate | Completed | apache/dubbo re-probed at the Plan 010 commit. Habit-loop latency is no longer a product problem: the worst call fell from 90.71 s to 0.019 s. Quality is unchanged: 244 of 6,710 sampled outgoing claims are facts, and 4,624 of 5,662 unresolved calls are still receiver-qualified. The addressable public-method subset is 63, below the go threshold of 100. **Verdict: no-go.** |
| Stage 0 closure: Amendment 1 | Completed | Plan re-aimed at static `ClassName.method()` calls (135 in the sample). Instance receivers deferred to [Follow-up 014](../followups/014_java_instance_receiver_calls.md), the supertype guard to [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md). No code changed. |
| Stage 1: ADR for Java static calls | Completed | [ADR 009](../adr/009_java_static_calls.md) accepted: a class-name receiver resolves only when nothing can obscure it, the target class declares no supertypes, and the target is its one declared `static` method inside the covered access subset (public, plus any access inside the enclosing class). Rejected alternatives recorded: capitalization heuristic, method-only binding checks, admitting target classes with supertypes, widening access ahead of evidence, provider-source re-reading, a shared-core kind. |
| Stage 2: Java quality fixtures and counters | Completed | 47 cases in five tests state what ADR 009 requires before any behavior changes: the covered and declined static calls, every binding introducer that obscures a receiver name, the provider edit sequence, the value receivers that must stay unresolved, and the work counters. Falsified by flipping the matrix switch: the three behavioral tests fail exactly where Stage 5 must deliver. `zig build test` 238/240, from 233/235. |
| Stage 3: Java method projection, class shape, and invalidation | Completed | Class shape and method modifiers are carried as MCP-visible extension labels; `java_members` reads them back as candidates; an aspect-grained channel reaches the readers of a changed `Class.method` pair and nothing else in the package. Measured: a one-method edit costs 1 reanalysis where 4 Java units share the scope, a body edit 0, a supertype edit 2 for two readers — with 0 declared dependencies and 0 propagation rounds behind it. No call fact emitted. |
| Stage 4: Reading a receiver name as a type | Completed | A qualified invocation's receiver is decided, and no call fact is emitted. A simple name is a class only where no parameter, local, field, `for`, `catch`, resource, lambda or pattern binds it, the enclosing class declares no supertypes, and `resolveType` names one current class inside the ADR 008 boundary; each failure carries its own reason. Locals bind from their declarator to the end of their block, exactly; the other introducers bind method-wide, which declines more and claims nothing. 25 matrix cases moved from pending to checked, and three falsification runs show each half bites. `zig build test` 248/250, unchanged. |
| Stage 5: Static call facts | Completed | `ClassName.method()` is a `CALLS` fact under every ADR 009 condition at once, and the matrix lost its switch: 49 cases, each asserting its answer. Candidates come from the names the unit writes, so one invocation costs **1** candidate whether the package holds 2 classes or 22. A resolved call declares a provider dependency; an unresolved one is reached by the hint it wrote, with **0** dependencies in the graph and **0** propagation rounds. Two Stage 3 tests were rewritten: their world — nothing populating hints — is what this stage ended. `zig build test` 249/251, from 248/250. |
| Stage 6: Follow-up discipline | Completed | Both deferred subsets re-measured whole-graph on the same clone, with the Stage 4 and Stage 5 binaries over the same input. Every unresolved family is identical to the unit except one: 3,930 calls whose receiver names a class became 2,214 facts and 1,716 target-side declines. Follow-up 014's value receivers (55,127 + 21,132) and Follow-up 013's guard (8,083 references, 6,206 receivers) are unchanged, and the Stage 4 run reproduced Stage 0's baseline exactly. One delta is recorded unexplained: +106 assertion records that are not conversions. |
| Stage 7: External remeasurement, documentation and closure | Completed | The Stage 0 sample was rebuilt and reproduces its table to the unit, so the comparison is like-for-like: **139** static-call facts against a floor of 100 and a prediction of 135, every one of them a public `static` target. The 4,624-call reason decomposes exactly into seven families plus those facts; references did not move. Memory unchanged (186 → 185 MB), habit-loop latency unchanged, index time +18% ReleaseFast and +77% Debug, one-file refresh 0.28 s → up to 1.00 s re-reading up to 363 of 4,050 units. Capability matrix, preview reference, `SPEC.md` and `MEMORY.md` updated; `GLOSSARY.md` checked and unchanged. |

## Plan Readiness Gate

Applied on 2026-09-19 before Stage 0, against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate).

**No hard fail. Execution proceeds to Stage 0.**

- Product behavior is explicit and does not conflict with `RULES.md`,
  `MEMORY.md`, the constitution, or the implementation. The plan states the
  exactness rule it will not cross, names the current frontend behavior it
  starts from, and keeps every new outcome inside existing relationship,
  resolution, producer, and evidence fields.
- Scope and non-scope are explicit and name what must not move: no build
  descriptors, no shared-core `module`/`IMPORTS`, no approximate assertions, no
  MCP tool shape change, no persistence, no Clojure or Zig semantics.
- Key decisions are recorded as decisions with rationale (D1-D10), and each
  external dependency has a stop and resume rule: D1 stops implementation until
  ADR 009 is accepted, D3 and D4 force a plan amendment if the ADR decides
  differently.
- Stages are ordered, each has concrete output artifacts, and none depends on a
  later stage's outcome. Stage 0 is a real gate with an arithmetic threshold
  rather than a judgement call.
- The Definition of Done is observable: counts in a named sample, fixture
  families, work counters, and named verification lanes.
- The risk matrix maps each guarantee to the lowest sufficient check and names a
  negative case for each.

One gate observation, recorded rather than fixed: the go threshold is stated on
the **sample**, not on the repository. Stage 0 therefore reports both, and the
verdict below follows the plan's literal text.

## Stage 0: Post-Plan-011 External Baseline And Addressability Gate

### Repository Identity

| Property | Value |
| --- | --- |
| Repository | [apache/dubbo](https://github.com/apache/dubbo) |
| Commit | `df9c5e13bc014ef492ec20824f8623a5e092a5b1` |
| Clone | `git fetch --depth 1` of that exact commit, outside this repository |
| Maven modules (`pom.xml` files) | 119 |
| Java source units | 4,050 (2,469 under `src/main/java`, 1,581 under `src/test/java`) |
| Working-copy size | 36 MB |

Identical to the Plan 010 probe on every count, so the comparison below is
against the same repository state, not a moved target. Its source is not
committed here; only the measurements are.

### Method, And Why Two Build Modes

Plan 010 did not record the optimization mode of its probe, and the difference
turns out to dominate every wall-clock number. Stage 0 therefore measured both:

- **Debug** (`zig build`), which reproduces Plan 010's ingestion cost of the same
  order and is the mode its table is comparable to;
- **ReleaseFast** (`zig build -Doptimize=ReleaseFast`), which is what the
  [preview reference](../mcp/local_preview.md) tells a user to run and therefore
  what a user actually feels.

Each run drives the real stdio server, one process per run, protocol
`2026-07-28`, warm filesystem cache, idle machine. Timing is per call, measured
around the request/response pair, single run.

### Ingestion Outcome

| Measurement | Plan 010 | Stage 0 Debug | Stage 0 ReleaseFast |
| --- | ---: | ---: | ---: |
| Source units indexed | 4,050 | 4,050 | 4,050 |
| Ingestion wall time | 17.5 s | 21.2 s | 2.8 s |
| Maximum resident set size | 290 MB | 351 MB | 186 MB |
| Peak memory footprint | 547 MB | 574 MB | 185 MB |
| Scan diagnostics | 0 | 0 | 0 |

The Debug growth from 17.5 s to 21.2 s is the ingestion regression Plan 010
predicted from its Stage 4 single-type imports and Plan 011 left unmeasured. It
is now measured, and it is the cost of the import stage, not of Plan 011: Plan
011 changed only query access paths.

Graph contents at the Stage 0 snapshot (`semidx_health`), against Plan 010:

| Measurement | Plan 010 | Stage 0 |
| --- | ---: | ---: |
| Definitions | 26,509 | 26,509 |
| Assertions recorded | 228,972 | 230,753 |
| Current facts | 88,498 | 90,439 |
| Current unresolved | 140,474 | 140,314 |
| Current approximate | 0 | 0 |
| `unsupported_construct` diagnostics | 58,300 | 58,300 |
| `confirmed_absence` diagnostics | 722 | 722 |

1,941 claims moved from unresolved to fact since Plan 010's snapshot, which is
the single-type import stage landing.

### The Habit Loop, Re-Measured

The Plan 010 question set, in the order the preview reference teaches. The Plan
010 column is its published latency table; the Debug column is the comparable
mode.

| Call | Plan 010 | Stage 0 Debug | Stage 0 ReleaseFast | Bytes |
| --- | ---: | ---: | ---: | ---: |
| Cold index to first answered call | 17.5 s | 20.9 s | 2.20 s | — |
| `semidx_health` (warm) | 2.96 s | **0.036 s** | 0.003 s | 6,693 |
| `semidx_outline` (root) | 0.17 s | 0.018 s | 0.001 s | 13,335 |
| `semidx_outline` (one module) | — | 0.015 s | 0.001 s | 2,121 |
| `semidx_repo_map` (one package directory) | 0.01 s | 0.012 s | 0.002 s | 15,303 |
| `semidx_find_definitions` (`name`) | 0.02 s | 0.019 s | 0.001 s | 4,003 |
| `semidx_find_definitions` (`name` + `path`) | 0.02 s | 0.018 s | 0.001 s | 2,353 |
| `semidx_references` (`incoming`) | 1.33 s | **0.018 s** | 0.001 s | 3,069 |
| `semidx_references` (`outgoing`) | — | 0.018 s | 0.001 s | 17,000 |
| `semidx_context` `depth=1` | 2.61 s | 0.018 s | 0.001 s | 70,166 |
| `semidx_context` `depth=2` | 90.71 s | **0.019 s** | 0.001 s | 70,428 |
| `semidx_context` `depth=3` | 90.21 s | **0.019 s** | 0.001 s | 70,428 |
| `semidx_refresh` (nothing changed) | 0.98 s | 1.07 s | 0.108 s | 1,244 |
| `semidx_refresh` (one file changed) | 0.89 s | 0.45 s | 0.108 s | 1,244 |

Entity: the `RpcInvocation` class in
`dubbo-rpc/dubbo-rpc-api/.../rpc/RpcInvocation.java`, the same one Plan 010 used
for its reference and neighborhood questions.

**The finding Plan 010 recorded as a product problem is gone.** The adoption
strategy names `semidx_context` the default focused-context tool; at 90 s it was
unusable on a repository this size, and it now answers in 19 ms in the same
build mode and 1 ms in the mode a user runs. `semidx_references incoming` fell
by the same shape, from 1.33 s to 0.018 s. Nothing about the answers changed:
the byte sizes are the same answers, and Plan 011 added and removed no
assertion.

**Refresh is unchanged and is now the largest habit-loop cost.** A no-op refresh
costs 1.07 s in Debug and 0.108 s in ReleaseFast, because a scan-based refresh
with no file watching walks every unit and compares content ids. Plan 011 said
this explicitly and put it out of scope; Stage 0 confirms it at external scale.
It is not a regression and it is not this plan's business.

### What Stays Unresolved, And Why

Sampled the same way as Plan 010: 1,200 of the 26,509 Java definitions, seed
`20260918`, asking `semidx_references` for every outgoing claim of each sampled
definition. The sampling harness is this stage's own and is not the Plan 010
process, but the sample size, seed and shape match and the claim total is
identical — **6,710 outgoing claims** — so the two are comparable.

| Claim | Resolution | Plan 010 | Stage 0 | Share |
| --- | --- | ---: | ---: | ---: |
| `calls` | unresolved | 5,662 | 5,662 | 84.4% |
| `references` | unresolved | 809 | 804 | 12.0% |
| `calls` | fact | 174 | 174 | 2.6% |
| `references` | fact | 65 | 70 | 1.0% |

3.6% of outgoing claims are facts, unchanged from Plan 010. Single-type imports
moved five reference claims in this sample, which is consistent with 1,941
across the whole graph.

Unresolved calls by reason:

| Reason | Count | Share of unresolved calls |
| --- | ---: | ---: |
| Receiver-qualified, receiver not resolved | 4,624 | 81.7% |
| No method of this name in the enclosing class | 698 | 12.3% |
| Enclosing class has supertypes | 231 | 4.1% |
| Overloads in the enclosing class | 104 | 1.8% |
| Invocation inside a nested class body | 5 | 0.1% |

Unresolved references by reason:

| Reason | Count |
| --- | ---: |
| Supertype guard on the enclosing class | 335 |
| Not declared in this unit, and no package reach | 322 |
| No current top-level class in that package | 61 |
| Single-type import unsatisfied (no such class, or out of scope) | 55 |
| Type parameter of the enclosing class or method | 16 |
| Qualified type name | 8 |
| Member type of the enclosing class | 6 |
| Source-root boundary | 1 |

By whether the target has source in the working copy: 716 unresolved references
name a type no indexed unit declares (dependency or JDK), and 88 name a simple
name some unit does declare. The second bucket is the only convertible one and
is 1.3% of all outgoing claims.

### The Addressable Receiver Subset

Every one of the 4,624 receiver-qualified unresolved calls was classified
offline against the plan's covered list, by parsing the sample's own source with
tree-sitter and mirroring the frontend's `resolveType` order and ADR 008
visibility exactly. A call counts as addressable only when all of the plan's
Stage 5 preconditions hold: covered receiver shape, covered binding introducer,
receiver type resolving to exactly one current top-level class inside the ADR
008 boundary, target class declaring no supertypes, exactly one method of that
name declared in it, and the invocation outside a nested class body.

Receiver expression shapes:

| Shape | Count | Share |
| --- | ---: | ---: |
| Simple identifier | 3,666 | 79.3% |
| Chained or field receiver | 789 | 17.1% |
| Class literal (`X.class`) | 73 | 1.6% |
| `super` | 29 | 0.6% |
| String literal | 31 | 0.7% |
| `this` | 26 | 0.6% |
| `new Type(...)` | 10 | 0.2% |

Outcome:

| Outcome | Count |
| --- | ---: |
| Addressable, public target method | **63** |
| Addressable, protected target method | 7 |
| Addressable, private target method (all `this.m()`) | 1 |
| Blocked | 4,553 |

Why the blocked calls are blocked, largest first:

| Blocker | Count |
| --- | ---: |
| Receiver type does not resolve under current rules | 1,311 |
| Class-name / static receiver, out of scope for this plan | 1,041 |
| Chained or field receiver expression | 789 |
| Declared type shape not covered (generic, array, wildcard) | 636 |
| Target class declares supertypes | 283 |
| Binding introducer not covered (for-each 214, lambda 112, catch 22, resource 3) | 351 |
| Class literal or string literal receiver | 104 |
| `super` receiver | 29 |
| Overloaded method in the target class | 7 |
| `new` expression type shape not covered | 2 |

And why receiver types do not resolve, which is the largest blocker:

| Reason | Count |
| --- | ---: |
| The enclosing class has supertypes, so `resolveType` declines cross-unit | 627 |
| A single-type import names a package where no indexed unit declares the class | 234 |
| The import reaches a class outside the ADR 008 boundary | 188 |
| No current top-level class of that name in the unit's package | 144 |
| Member type or type parameter of the enclosing class or method | 55 |
| Same package, out of scope | 63 |

Spot-checked against source. For example
`dubbo-cluster/src/test/java/.../match/AddressMatchTest.java:38`
calls `addressMatch.setCird(...)` on a local of type `AddressMatch`, whose
provider `dubbo-cluster/src/main/java/.../match/AddressMatch.java` is a class
with no supertypes declaring exactly one public `setCird`, reachable by ADR
008's standard-layout test-to-main rule. That is precisely a Stage 5 fact, and
the plan would produce it.

### Go/No-Go Verdict

| Start Rule condition | Required | Measured | Met |
| --- | --- | --- | --- |
| Local Plan 011 work-bound lane still proves anchored work | pass | `zig build test-core -Doptimize=ReleaseFast`: 98/98 | Yes |
| Public-method addressable receiver subset in the external sample | min(100, 5% of 4,624 = 231) = **100** | **63** | **No** |

**Verdict: no-go.** The plan stops before ADR and code work, as its Stage 0 Done
condition requires.

For scale, and not as a substitute for the threshold: the sample covers 1,200 of
26,509 definitions (4.5%), so 63 in the sample is of the order of 1,400
repository-wide. The plan states its bar on the sample, and this log does not
reinterpret it.

### Where The Java Value Actually Is

The same classification measured three alternatives, so the decision to revise or
abandon has numbers behind it rather than intuition. Counts are additional
public-method invocations in the same sample.

| Direction | Additional exact public facts | Exactness risk |
| --- | ---: | --- |
| **A. Static `ClassName.method()` calls** (currently plan non-scope) | **135** | None new. The receiver is a type name, resolved by the existing `resolveType`; the target must be a unique public static method of a class with no supertypes, inside the ADR 008 boundary. No local type environment is needed at all. |
| B. Admit generic and array base types into the covered receiver bindings | 18 | Low. The base type is a plain `type_identifier` under one wrapper. |
| C. Admit target classes that declare supertypes when the name is declared once in the class itself | 211 | **Rejected by evidence.** A second pass walked the target hierarchies of 210 of those 211 (it re-derives `this` and identifier receivers only): **none** is closed in indexed source. Every one reaches a JDK, framework, or dependency supertype, so an inherited overload cannot be ruled out and the target would be a guess. |

Direction A alone clears the plan's own 100 bar, and it is cheaper than the
receiver work: it needs no method-body type environment, no binding-introducer
poison rules, and no new class-shape evidence beyond what the target class
already carries. It is also the bucket users meet first in real Java — the
measured examples are `StringUtils.isNotEmpty(...)`,
`CollectionUtils.isNotEmpty(...)`, `NetUtils.getLocalHost()`.

A further 247 static calls are blocked only because the **referring** class has
supertypes, which is the `resolveType` guard, not the static-call rule. That is
the supertype-guard item below, and it compounds with direction A rather than
competing with it.

### The Decision

Direction A was chosen on 2026-09-19 and recorded as
[Amendment 1](../plans/012_java_semantic_quality_without_query_regression.md#amendment-1-from-instance-receivers-to-static-calls):
the plan keeps every rule it had and changes its subject from instance receivers
to static calls. Direction B stays unimplemented and becomes
[Follow-up 013](../followups/013_java_supertype_guard_relaxation.md); the
original instance-receiver subject becomes
[Follow-up 014](../followups/014_java_instance_receiver_calls.md), so the 63 and
their blockers are not lost with the amendment.

One exactness rule had to be settled before the amendment could be trusted,
because it could have eaten the 135. Java lets a variable obscure a type of the
same name (`foo.m()` where `foo` is both a local and a class means the local),
so reading a receiver name as a class requires proving that nothing binds that
name — including a field inherited from a supertype, which the working copy may
not be able to see. The strict rule is therefore: no parameter, local, field, or
other binding introducer in scope may declare the name, and the enclosing class
must declare no supertypes.

Measured on the same sample, that rule costs **nothing**: all 135 already
satisfy it, because every one resolves its receiver through `resolveType`, which
already declines cross-unit names inside a class with supertypes. Same-unit
class-name receivers contributed 0 to the subset, which is the case where the
rule would have had to do work of its own.

### Supertype Guard Opportunity

Measured on the same sample, as Stage 0 requires and without implementing
anything.

The supertype guard is the largest unresolved-reference reason at 335 of 804.
But as an opportunity it is small, because most of what it guards would not
resolve anyway:

| If the guard were lifted, the reference would | Count |
| --- | ---: |
| Still not resolve: no current top-level class in that package | 172 |
| Still not resolve: the import names a package with no such class | 100 |
| Still not resolve: the import reaches a class outside the ADR 008 boundary | 25 |
| Resolve to exactly one class through a single-type import | 22 |
| Resolve to exactly one class in the same package | 16 |

So lifting the guard entirely would convert **38** of 335 references in this
sample. And making it safe rather than simply lifting it needs a closed
hierarchy, which this repository almost never has:

| Enclosing class hierarchy, for the 335 guarded references | Count |
| --- | ---: |
| Implements interfaces, so the hierarchy is open | 218 |
| Superclass itself has supertypes (deeper chain) | 56 |
| Superclass shape not a simple name | 36 |
| **Closed one-level source hierarchy** | **13** |
| Superclass has no source in the working copy | 12 |

The plan's own follow-up threshold is 50 references in the sample or 1% of
sampled outgoing claims, whichever is smaller — that is 50. Both the convertible
count (38) and the safely convertible count (13) are below it. **No follow-up is
recorded for the supertype guard**, and the plan's D9 position that it is not
worth its own plan is confirmed by measurement rather than assumed.

The one place the guard does pay is direction A above: 247 static calls are
blocked by it, which is a call-side effect the reference-side measurement does
not show.

### The Plan 011 Claim, Now Externally Observed

Plan 011 closed with the honest statement that external Java latency was not
re-measured and that its product claim rested on local work bounds. Stage 0
answers it:

- The claim is **supported by external observation**, not only by work bounds.
  Every anchored query on apache/dubbo is now in the tens of milliseconds in
  Debug and in single milliseconds in ReleaseFast, and the traversal that cost
  90.71 s costs 0.019 s.
- The local work-bound lane still holds: `zig build test-core
  -Doptimize=ReleaseFast` passes 98/98, including the external-scale proof at
  244,559 assertions.
- No measured work contradicts it.

Deterministic counters for dependency declarations, propagation rounds, and
propagation exhaustion are **not observable through the MCP surface**, which
exposes none of them. The plan allows exactly this case: the limitation is
recorded, and the local work-bound lane was run instead.

### What This Measurement Does Not Claim

- **The addressability classification is not the frontend.** It mirrors
  `resolveType`'s order and ADR 008's rules in a separate offline tool over the
  same sources. It is conservative by construction — every shape it cannot prove
  is counted as blocked — so the addressable count is a lower bound, which is
  what the plan asks for. A frontend implementation could differ in edge cases.
- **One repository, one sample.** Dubbo is a Maven, interface-heavy, test-rich
  codebase. The static-call and supertype findings are shaped by that, and a
  second repository could move them.
- **Single-run timings.** No best-of-N, no cold-cache measurement. The
  conclusions drawn from them are order-of-magnitude conclusions (90 s to 0.019 s),
  not precise costs.
- **Debug and ReleaseFast are not comparable to each other**, only each to
  itself. Plan 010's mode is unrecorded, so the Debug column is the honest
  comparison and is labelled as such.

### What Was Fixed, And Where

| Finding | Commit | Effect |
| --- | --- | --- |
| 2, 3, 4 | `ffb8bf8` | A unit with an on-demand static import resolves no simple-name receiver; `java.static` became a tri-state whose `unknown` declines as unrecorded; the two unreachable declines stay, with their lookup-order assumption pinned by a test |
| 1 | this commit | A unit that moves to another directory is reanalyzed and marks everything it exposes as changed; a rename inside one directory still re-reads nothing |

Finding 7 stays with
[Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md),
and finding 6 moved to its own entry,
[Follow-up 018](../followups/018_unexplained_assertion_delta.md), so that it has
an owner rather than a mention in a closed plan's residual risk.

017 is not closed, and the reason is the point of it. A harness now exists —
`scripts/java-claim-sample.py`, a developer tool no build lane refers to — whose
sample is specified well enough to be drawn without it: definitions are ranked
by `sha256(seed + "\n" + key)` over `path\nline\nrole\nname`, so a
reimplementation in any language draws the same sample from the same seed. It
also refuses to lose a reason family: a claim no family matches is counted as
`unclassified` and its explanation printed, which is the check Stage 7's
eight-row table did not have.

It was verified on what is here — the Java fixtures, a tree written to reach
every family (14 of 17 reached; the three that stayed empty are exactly the
three Follow-up 016 records as unreachable), two runs of one seed byte-identical,
a different seed drawing a different sample, and a Zig root where all 117
unresolved calls land in `unclassified` with their explanations printed. None of
that is a clone of `apache/dubbo`. Stage 0's selection was never recorded and
cannot be recovered, so this harness produces a **new** baseline rather than
confirming the old one, and Plan 012's 6,710 / 5,662 / 174 / 313 / 139 stay
unverifiable by anyone. Closing 017 here would assert a check that did not run.

### Verification

Re-run after both fixes: `zig build test-core`, `zig build test`,
`zig build test-mcp`, `zig build dogfood` and `zig build preview-gate` all exit
0, with 257 tests passing and 2 skipped against 249/2 before the review.

The table below is the review's own pass, against `6a47ba5`.

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the semidx target |
| `zig build test-core -Doptimize=ReleaseFast --summary all` | 5/5 steps, 98/98 tests passed, 763 ms, MaxRSS 469 MB |
| `zig build` | semidx-dev and semidx-mcp built |
| `zig build -Doptimize=ReleaseFast` | semidx-mcp built |
| External probe, Debug and ReleaseFast | Results above |

Not run, and why: `zig build test`, `zig build test-mcp`, `zig build dogfood`,
and `zig build preview-gate` were not run, because Stage 0 changed no code in
this repository. `zig fmt --check` likewise has nothing to check.

### Residual Risk And Next Step

- **Next step is Stage 1**: ADR 009 for Java static calls, under the amended
  plan. No Java semantic code may change before it is accepted.
- The 135 is a lower bound produced by an offline classifier, not by the
  frontend. Stage 7 measures what the implementation actually converts, and the
  plan's closure bar (at least 100, and at least 80% of the accepted-access
  subset) is stated against it. If the implementation reaches fewer, the gap is
  a finding to record, not a reason to widen the rule.
- The external clone lives outside this repository at
  `~/.cache/semidx-external/dubbo` at commit `df9c5e1`. It is evidence, not a
  conformance target, and nothing in a local lane depends on it.
- The ingestion regression from 17.5 s to 21.2 s in Debug is now measured and
  attributed to the Plan 010 import stage. It is not tracked as a defect here; at
  2.8 s in ReleaseFast it is not a product problem.

## Stage 1: ADR For Java Static Calls

[ADR 009](../adr/009_java_static_calls.md) is committed with
`status: accepted` and listed in [docs/adr/README.md](../adr/README.md). It
answers all eight questions of constitution section 11 and records a rejected
alternative for every decision it makes.

### What It Decided

| Question | Decision | Rejected alternative |
| --- | --- | --- |
| What does a static `CALLS` fact mean? | The one `static` method the named class declares; static methods are not dispatched, so there is no dispatch question left open | Recording the call to any method of the class, which would assert a call Java does not compile |
| When is a receiver name a type? | Only when no binding introducer in scope declares the name **and** the enclosing class declares no supertypes, so no inherited field can obscure it | Trusting the capitalization convention; checking only the enclosing method's bindings |
| May the target class declare supertypes? | No. An inherited overload could change the selected target and a declared method may hide an inherited one | Resolving when the name is declared once in the class itself — worth 211 in the sample, exact in none of them |
| Which access is covered? | `public`, plus any access when the target class is the top-level class enclosing the invocation | Admitting package-private and protected now, ahead of any measurement |
| How is class shape and `static` evidence carried? | Additive Java extension labels on existing Java definitions | Re-parsing provider source during lookup; passing provider trees across the frontend contract; a shared-core kind |
| What happens to a non-static method named through a class? | Its own unresolved reason, distinct from "no such method" | Folding it into the missing-method reason |

The obscuring rule is the one decision that could have eaten the plan's
denominator, and it does not: all 135 addressable calls already satisfy its
strictest form.

### Drift Control

Checked against the plan's source-of-truth list before the ADR was committed.

| Document | Outcome |
| --- | --- |
| `ARCHITECTURE_CONSTITUTION.md` | No conflict. The eight answers are in the ADR; sections 3, 5, 6 and 7 are the load-bearing ones and each is preserved rather than argued around. |
| `RULES.md` | No conflict. ADR procedure followed, no attribution, English, single owner per rule. |
| [ADR 003](../adr/003_reject_name_match_assertions.md) | Consistent. The obscuring rule exists precisely so a class name is never selected by name alone. |
| [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) | Unchanged. Static-call receiver resolution calls `resolveType` as it is; no guard is widened. |
| [ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md) | Precedent followed: a narrow, evidence-bound cross-unit `CALLS` fact. |
| [ADR 008](../adr/008_java_visibility_boundaries.md) | Unchanged. The receiver class must be inside the same visibility scope, with that record's own explanations preserved. |
| `SPEC.md` | One row will change at Stage 7: the invalidation row names Java package-export invalidation as the only producer, and Stage 3 adds an aspect-grained class-shape channel. No conflict now. |
| `CORE.md` | No admission requested. Method signatures stay part of Java method identity; no `module`, `IMPORTS`, inheritance, or dispatch kind. |
| [Capability matrix](../spec/capability_matrix.md) | **One stale claim corrected now**, not deferred: the Java "Known false negatives" row demanded a fresh supertype-guard measurement before further Java widening. Stage 0 made that measurement, so the row now carries it and links Follow-up 013. The covered static-call case is added at Stage 7, after the behavior exists. |
| `MEMORY.md` | Updated with the amended plan state in the same series of commits. |
| `GLOSSARY.md` | No entry added. Obscuring proof, binding introducer, covered access subset, and static target are Java-specific normative terms owned by ADR 009. Class shape is the one project-wide candidate; Stage 7 decides it. |
| [Follow-up 011](../followups/011_java_cross_module_visibility.md) | Untouched. No cross-module visibility is admitted. |
| [Follow-ups 013](../followups/013_java_supertype_guard_relaxation.md) and [014](../followups/014_java_instance_receiver_calls.md) | Consistent: the ADR names both as not enabled. |
| [Adoption strategy](../design/002_product_adoption_strategy.md) | Served. Static utility calls are the shape of "who calls this" a Java reader asks first, and they are answered from the graph rather than from a name match. |
| `src/frontends/java.zig` | Read before deciding. `resolveType`'s order, its explanations, and `emitInvocation`'s qualified-receiver reason are the mechanisms the ADR builds on; none is changed by this stage. |

### Verification

| Command | Result |
| --- | --- |
| Relative-link check over the plan, progress log, ADR index, and follow-ups | No missing targets |
| `zig build` lanes | Not run: no code changed in this stage |

### Residual Risk

- The ADR is `accepted` as the procedure requires, but human review has not
  happened yet. If review changes a decision, Stage 2 stops until the ADR and
  the plan agree, per the plan's Stage 1 Done condition.
- The access subset is deliberately narrower than what is decidable. If Stage 7
  finds the public-only subset leaves obvious value on the table, that is a
  future plan with its own measurement, not a widening during implementation.

## Stage 2: Java Quality Fixtures And Counters

The exactness target is executable before any behavior changes. Five tests in
`tests/vertical_slice_test.zig` state what ADR 009 requires, and the frontend
answers none of them yet.

### The Matrix, And Why It Passes Today

Every case is written against ADR 009 and says what the call must **become**,
not what it currently gets. One constant decides which half is asserted:

```zig
const static_calls_resolved = false;
```

While it is false, a covered case asserts only that the call exists and is not a
fact; a declined case additionally asserts that its designator survives intact.
Stage 5 flips it, and the matrix turns from a specification into a regression
test. That is the plan's "pin cases, not old reason strings": nothing here
asserts the one reason the frontend has today for every receiver, because Stage 4
and Stage 5 are expected to replace it.

A switch like that is worthless if the cases behind it are vacuous, so it was
falsified rather than trusted: flipping it to `true` fails all three behavioral
tests, each at the case it should fail at — `expected .fact, found .unresolved`
for the covered calls and `TestUnexpectedExplanation` for the obscuring
families. Flipped back, the lane is green.

| Test | Cases | What it pins |
| --- | ---: | --- |
| `the static-call matrix pins what each covered and declined case must answer` | 18 | Five covered calls (same package, test-to-main root, single-type import, same unit, same class private) and thirteen declined ones (overloaded, non-static, three access levels, private in another top-level class of the same unit, missing method, target class with supertypes, no such class, nested class body, outside the ADR 008 root, enclosing class with supertypes) |
| `a receiver name any binding introducer declares is not read as a class` | 11 | Parameter, spread parameter, local, field, enhanced `for`, `catch` parameter, try-with-resources resource, lambda parameter, type pattern, record pattern — each obscuring the name; plus the one case that must still resolve, a call *before* a local declaration of that name |
| `provider method and class-shape edits decide what a static call may claim` | 9 | The same call re-decided after each provider edit: method removed, restored, overloaded, made non-static, moved out of the covered access, given a supertype, given it back, and finally the class moved across the source-root boundary |
| `a receiver that is a value stays unresolved, whatever the static rule admits` | 9 | Local, field, parameter, `new Other()`, chained call, string literal, class literal, `this`, `super` — the receivers Follow-up 014 owns, which the static rule must not pick up on the way past |
| `the write path and the java frontend report the work they do` | — | The counters below are readable and move |

The fixtures discriminate rather than merely exercise. Every shadowing receiver
is a value of a type whose `make` is an **instance** method, while the class's
`make` is **static**: a frontend that read the bound name as a class would name a
different method, not the same one by another route, so a false fact cannot hide
behind a passing assertion.

### The Reason Families Stage 5 Owes

The declined cases name the fragment each reason must contain. This is the
contract Stage 5 implements, and the list is the ADR's reason families made
executable:

`overloads are not resolved`, `is not static`, `access`, `no method of this
name`, `supertypes`, `no current top-level class`, `class body declared in the
method`, `source root this unit can see`, `declared here as a binding`, and
`receiver` for a value receiver.

`receiver` is the one family that already holds, so those nine cases are marked
`settled` and their reason is checked now rather than at Stage 5. A negative
control confirmed the check bites: replacing one fragment with a string the
frontend cannot produce fails the test with the explanation it did produce.

### Counters

Test-only, compiled away outside a test build, following `core.graph.work`:

| Counter | Where | What it counts |
| --- | --- | --- |
| `semidx.frontends.java.work.method_candidates` | `src/frontends/java.zig` | Method candidates examined while deciding invocation targets. Candidates, not invocations: the term at risk is the one inside the decision. |
| `semidx.work.upkeep_reanalyses` | `src/root.zig` | Units reanalyzed by upkeep because something they read changed. Previously visible only through `ScanOutcome`, which the edit and add paths do not fill in. |
| `semidx.work.propagation_rounds` | `src/root.zig` | The deepest chain any batch walked since the last reset. |
| `semidx.work.propagation_exhausted` | `src/root.zig` | Whether any batch stopped at `max_propagation_rounds`. |
| `Dependencies.Propagation.rounds` | `src/core/dependencies.zig` | The rounds one propagation spent. The only shared-core change in this stage, and the reason `zig build test-core` is its narrow lane. |

Dependency declaration count needed nothing new: `index.graph.dependencies.count()`
already answers it, and the counters test asserts it.

The counters test pins the current shape rather than a future one: deciding the
invocations in a two-class unit examines at most that unit's own methods, one
provider edit reanalyzes exactly one dependent, propagation spends two rounds —
one to reach the dependent, one to find it leads nowhere further — and nothing
exhausts its budget.

### Risk Matrix Update

| Plan risk row | State after Stage 2 |
| --- | --- |
| A receiver name is a type only when nothing obscures it | Fixtures exist for every binding introducer ADR 009 names, including the inherited-field case and the one case that must still resolve. Evidence is pending Stage 4. |
| Static call facts are exact | The covered and declined cases are enumerated with their targets. Evidence is pending Stage 5. |
| Unresolved remains distinguishable | Every declined case carries its own reason fragment, and the families are distinct. |
| Instance receivers stay unresolved | **Covered now**, and asserted now rather than at Stage 5: nine value receivers keep the reason they have. |
| Incremental freshness holds | The provider-edit sequence exists as a fixture; the reach it needs is Stage 3's to build. |
| Write path stays bounded, dependency propagation stays useful | Counters exist and are asserted at the current shape; the bounds are Stage 3 and Stage 5's to tighten. |

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the semidx target |
| `zig fmt --check build.zig src tests` | Clean |
| `zig build test-core` | 97/98 passed, 1 skipped (external-scale proof, skipped in debug by design) |
| `zig build test` | 238/240 passed, 2 skipped — from 233/235 before this stage |
| `zig build test-mcp` | 29/30 passed, 1 skipped |
| Falsification: `static_calls_resolved = true` | Three tests fail at the cases Stage 5 must deliver; reverted |
| Negative control on a `settled` reason fragment | Fails with the explanation the frontend actually produced; reverted |

Not run, and why: `zig build dogfood` and `zig build preview-gate` are closure
lanes and no MCP-visible output changed in this stage — the counters compile away
outside a test build and no assertion, label, or payload field moved.

### Residual Risk

- **The covered cases assert little until Stage 5.** That is the design, and the
  falsification run is what keeps it honest. A future agent that changes the
  matrix must re-run that flip rather than assume it.
- **`beforeLocal` forbids the cheap implementation.** A Stage 4 that poisons a
  name for the whole method, rather than from its declaration onward, is exact
  but fails this case. That is deliberate: Java's scope rule is the rest of the
  block, and the fixture holds Stage 4 to it rather than letting the easier rule
  in silently.
- **One snippet is parsed, not compilable.** `bySpread` binds the name to a
  varargs array, and no valid Java call through one reaches this rule. What it
  pins is the binding, which is the rule under test.
- **The counters are process-global test-only variables.** Tests reset them
  before use, which is correct while Zig runs a test binary's tests in sequence;
  a parallel test runner would need per-test isolation instead.

## Stage 3: Java Method Projection, Class Shape, And Invalidation

The candidate infrastructure a static call needs exists, and it emits no call
fact. What a class is — its methods, their access, whether they are `static`,
and whether it declares supertypes — is now carried by the graph, readable by a
later analysis, and watched by an invalidation channel of its own.

### Class Shape Is Carried, Not Re-Read

A unit is analyzed from its own source. Another class's modifiers are not in it,
the frontend contract hands out no provider bytes or trees, and re-reading the
provider per lookup would make every answer a parse. So the frontend records
what it declares, as extension labels on the definitions themselves:

| Label | On | Values |
| --- | --- | --- |
| `java.supertypes` | class | `none`, `declared` |
| `java.access` | method | `public`, `protected`, `package_private`, `private` |
| `java.static` | method | `true`, `false` |

They are MCP-visible, which is a payload change even though no tool contract
moved, so it is proved rather than asserted: a new `zig build test-mcp` test
starts a server on a Java unit and reads the four labels back out of a
`semidx_find_definitions` result.

`package_private` is a value rather than an absence, because a method that names
no access keyword is package-private by Java's decision, not by missing
information. The projection keeps a separate `unknown` for a definition that
carries no label at all — something other than the current Java frontend
recorded it — and `unknown` declines rather than assuming the permissive case.

### The Projection

`src/frontends/java_members.zig`, the same discipline as `java_packages`: it
creates no entity, no signature kind, no inheritance relationship, decides
nothing, and re-reads the graph on every call.

- `classShapeOf` answers only for a current top-level Java class fact in a live
  unit, so a stale or failed provider offers nothing to select against.
- `methodsOf` returns the methods a class declares, in declaration order, with
  their access and `static` marker.
- `select` answers `missing`, `overloaded` with a count, or `unique` with the
  one method — it never returns the first of several, because choosing between
  overloads needs argument types this frontend does not have.

### The Invalidation Channel, And Why It Is Not The Package One

The existing `java_packages` export path detects a package plus a top-level
class name appearing or disappearing. A method's access changing is invisible to
it, and folding a shape fingerprint into it would mark the whole package changed
for a one-method edit — reanalyzing declarers and importers for a change none of
them can see.

So class shape travels on its own channel, at two granularities:

| Aspect | Changes when | Reaches |
| --- | --- | --- |
| `Class` | the class appears, disappears, or starts or stops declaring supertypes | every unit hinted as a reader of any method of that class |
| `Class.method` | that name's whole selection changes: count, access, or `static` | the units hinted on that pair |

Both exist because they are different questions. A class-level change can change
the answer for a method name the class does not even declare — which is the
reader whose call is unresolved today and could become a fact tomorrow, and the
one no `Class.method` aspect can reach. Method aspects carry the class's
supertype shape too, so a supertype edit reaches pair readers directly rather
than only through the class bucket.

`Upkeep` captures the shape a unit exposes before and after the step that
changes it, beside the package-export capture that was already there, and marks
only the aspects that actually differ.

### Measured

Four Java units share the fixture's scope: the provider, a reader hinted on one
of its methods, a second declarer in the same package, and a unit that imports
from it. Every number is a test assertion, not an observation.

| Change to the provider | Units reanalyzed |
| --- | ---: |
| A method body | **0** |
| `public` dropped from one method | **1** |
| `static` dropped from one method | **1** |
| One method gains an overload | **1** |
| One method removed | **1** |
| One method appears where the reader found none | **1** |
| A declared supertype added, two readers on two different methods | **2** |
| A new class appears in the package | **more than 1** — the package channel, still doing its own job |

The one in every row is the hinted reader. The sibling declarer and the importer
are never among them, which is the claim this stage exists to make.

And the reach is measured where no dependency could carry it: **0** declared
dependencies among those readers, **0** propagation rounds, propagation never
exhausted. An unresolved call read nothing, so it declared nothing, so nothing
but the hint can reach it — and the hint does.

### Decisions Worth Recording

- **Hints are keyed by the simple name as written, not by a resolved provider.**
  A reader that could not resolve its receiver has no provider to key on, and
  that reader is exactly the one the channel exists for. The cost is accepted
  over-invalidation: a class of the same name in an unrelated module reanalyzes
  readers whose answer cannot change. That is a pass and no claim, and it is the
  side the plan requires — a hint may over-invalidate, never under.
- **The aspect diff is quadratic in one unit's own classes and methods**, the
  same shape as the existing package-export diff, and bounded by work the edit
  already pays to analyze.
- **Provider dependencies for resolved targets are not declared yet**, because
  no target resolves yet. `declareProvider` already exists for the type rule and
  Stage 5 uses it for method targets.

### Documentation

`SPEC.md`'s invalidation row named Java package-export invalidation as the only
producer and listed aspect-grained invalidation as still to specify. It now
names class shape as the second producer and the first aspect-grained one, and
what remains open is narrowed to whether a hint should key on a resolved
provider rather than a simple name. The capability matrix is Stage 7's, after
the behavior exists.

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Clean |
| `zig build test-core` | 97/98 passed, 1 skipped |
| `zig build test` | 248/250 passed, 2 skipped — from 238/240 after Stage 2 |
| `zig build test-mcp` | 30/31 passed, 1 skipped — from 29/30, the new label-visibility test |
| `zig build preview-gate` | 14/14 steps, 6/6 tests, every hard gate passed |

Existing Java package and import tests pass unchanged; no test needed editing to
accommodate the labels or the channel.

### Residual Risk

- **Nothing populates the hints yet.** Stage 5 does, from the receiver names the
  frontend reads. Until then the `Upkeep` path is proved with seeded hints,
  which is what the plan asks for, and the frontend half is unproved.
- **The name-keyed hint over-invalidates across modules**, as recorded above.
  Narrowing it to a resolved provider would lose the unresolved reader, so it
  needs a second key rather than a replacement; `SPEC.md` now carries that as
  the open question.
- **The labels add bytes to every Java definition item.** Stage 7 owes the
  measurement against the Stage 0 baseline.
- **`zig build dogfood` and `zig build preview-gate` are timing-sensitive on a
  cold or busy machine.** The first two runs after a fresh compile failed with
  no assertion message, and the test binaries passed when run directly; four
  consecutive runs since have passed, including the gate's 14/14. This is **not
  a Stage 3 regression**: it reproduces at `HEAD` with this stage's changes
  stashed. Stage 7 depends on both lanes, so it is recorded here rather than
  left to be rediscovered.

## Stage 4: Reading A Receiver Name As A Type

The frontend now decides what a qualified invocation's receiver is. It still
records no call fact, and that is the point of the stage: the receiver decision
is provable on its own, because every declined call now names the condition that
declined it instead of sharing one reason with every other receiver.

### The Decision, And Why Its Order Is Not Cosmetic

| Asked | Reason family when it fails |
| --- | --- |
| Is the receiver a single identifier? | `qualified by a receiver this frontend does not resolve` |
| Is the invocation outside a class body declared in the method? | `class body declared in the method` |
| Is the name free of every binding in scope? | `declared here as a binding` |
| Does the enclosing class declare no supertypes? | `the enclosing class has supertypes` |
| Does `resolveType` name exactly one current top-level class? | `resolveType`'s own explanation, carried through |

The order is the order in which an answer stops being available, not a
preference. A receiver that is not a simple name carries no name to read at all.
A name a binding claims is a value whatever else exists, so it is asked before
anything about classes. A class that declares supertypes may inherit a field
nobody in the working copy can see, so the name cannot be cleared even when
nothing visible claims it — which is why that guard is asked before
`resolveType` rather than left to it: `resolveType` answers a name declared in
the same unit before it reaches its own supertype check, and a receiver must not
slip through there.

### Two Tiers Of Binding, And Why Only One Is Exact

Java scopes its binding introducers differently, and following every one of them
exactly would buy nothing this project measured. So the frontend keeps two sets:

| Tier | Holds | Scope it is read with |
| --- | --- | --- |
| Method | parameters and spread parameters, the enclosing class's fields, and every name a `for`, `catch`, resource, lambda, type pattern or record pattern binds anywhere in the method | the whole method |
| Local | local variable declarators | from the declarator to the end of its block, exactly |

The method tier over-declines: a call written before a `catch` parameter of the
same name is declined although Java would not bind it there. That is a decline
and never a wrong fact, and it is the side of the error this plan requires.

The local tier is exact because the cheap rule would be wrong in the visible
direction. `void beforeLocal() { Util.make(); Other Util = null; }` is a class
name followed by a variable of that name, and a frontend that poisoned the
method would read the call as a value it cannot resolve — losing a fact Java
grants. The walk pushes a local's names after the declarator it is written in
and drops them when its block ends, which is Java's rule rather than an
approximation of it.

Collection is lazy and once per method: a method with no simple-name receiver
never walks for bindings, and a method with ten receivers walks once.

### Proving A Receiver Was Read As A Class Before Any Fact Exists

A stage that emits no fact still has to show which receivers it read as classes.
It shows it in the reason: a receiver read as a class leaves the call unresolved
for want of the method — "the receiver names class `Util`, and the method it
names there is not resolved" — and a receiver read as anything else says what it
was read as instead. So the matrix's covered cases, which assert a fact only
once Stage 5 lands, now assert that much now:

```zig
try testing.expect(!call.resolution.isFact());
try expectExplanation(call, receiver_read_as_a_class);
```

That is what makes `beforeLocal` a test of the lexical rule rather than a
placeholder: it is a covered case, so it must report a class where `byLocal`,
one line away, reports a binding.

### One Node Kind, Not One Rule, Was Added To `resolveType`

A type position writes a simple name as `type_identifier`; a receiver writes the
same name as `identifier`, because the parser cannot know which it is — that is
the question ADR 009 makes the frontend answer. `resolveType` now accepts either
spelling and is otherwise untouched, so type parameters, member types, static
imports, non-class types, single-type imports, the same-package rule and the
ADR 008 boundary keep their meanings and their explanations. No existing answer
can move, because no type position parses as an `identifier`, and the type
tests pass unchanged.

### What The Matrix Now Checks

Stage 2 wrote 47 cases and checked the 9 that were already settled. Stage 4 adds
two lambda spellings the ADR names and Stage 2 had not spelled out — inferred
parameters `(Util, rest) -> …` and a typed lambda parameter — and turns 25 more
cases from pending into checked.

| Test | Cases | Checked now | Still owed by Stage 5 |
| --- | ---: | ---: | ---: |
| The static-call matrix | 18 | 9 | 9 |
| A receiver name any binding introducer declares | 13 | 13 | 0 |
| Provider method and class-shape edits | 9 | 3 | 6 |
| A receiver that is a value | 9 | 9 | 0 |

Every reason family Stage 4 owns is among them: bound name, enclosing class with
supertypes, no current top-level class of that name, outside the ADR 008 root,
receiver that is not a simple name, and class body declared in a method.

### Falsified, Not Trusted

Three runs, each reverted:

| Change | What failed |
| --- | --- |
| Locals collected method-wide instead of per block | `beforeLocal`: the receiver reported a binding where a class was owed |
| The binding check skipped entirely | `byParameter`: the receiver reported a class where a binding was owed |
| The `inferred_parameters` branch removed | `byInferredLambda`: the same, for the one spelling Stage 4 added |

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the semidx target |
| `zig fmt --check build.zig src tests` | Clean |
| `zig build test-core` | 97/98 passed, 1 skipped |
| `zig build test` | 248/250 passed, 2 skipped — unchanged; this stage strengthened existing cases rather than adding tests |
| `zig build test-mcp` | 30/31 passed, 1 skipped |
| `zig build dogfood` | Exit 0 |
| `zig build preview-gate` | Exit 0, 14/14 steps, 6/6 tests, 28 hard passes |

Unresolved explanations are MCP-visible, which is why `test-mcp` and the gate
are in this stage's lane rather than left to closure.

The gate prints `failed command:` lines for individual test binaries and then
reports success with exit 0. Stage 3 recorded runs that "failed with no
assertion text"; what this stage observed is that shape — the lines appear while
the build's own verdict is success. Read the exit code and the summary, not the
intermediate lines.

### Residual Risk

- **A provider that leaves the caller's source root leaves the caller's answer
  stale.** Probed by marking the boundary case in the provider-edit test
  `settled`: after `renameUnit` moves `Util` out of the root, the caller still
  says "the receiver names class `Util`", because it declared no dependency and
  nothing hints it. It is a stale unresolved explanation and never a stale fact.
  Stage 5 closes it by populating the Stage 3 reader hints from the receiver
  names read here; the case stays unsettled in the fixture until it does, and
  the probe was reverted.
- **The method tier over-declines**, as designed and recorded above. The name
  key is the same trade Stage 3 accepted on its hints: a pass, never a claim.
- **A shared constant became a formatted explanation per call.** Every
  receiver-qualified invocation used to carry one interned sentence; now it
  carries one naming the condition that failed, and two of those name the
  receiver. The graph interns by value, so the cost grows with distinct receiver
  names rather than with calls, but it is new bytes in memory and in every
  response that shows an unresolved Java call. Stage 7 measures both against its
  baselines rather than assuming the growth is noise.
- **Every method with a simple-name receiver is walked once more.** Bounded by
  the method and paid only where a receiver asks, but it is new work on the
  index path, and Stage 7 owes the external measurement.
- **Follow-up 014's marker changed.** Value receivers no longer share one
  reason: a simple name a binding claims now says so, while `this`, `super`,
  literals, field accesses and chained calls keep the old wording. The follow-up
  records both families so a re-measurement counts the whole subset.

## Stage 5: Static Call Facts

`ClassName.method()` is a `CALLS` fact. The matrix Stage 2 wrote as a
specification and Stage 4 answered by half is now a regression test with no
switch left in it: 49 cases, every one asserting the answer rather than what it
owes.

### What Had To Be True At Once

ADR 009's nine conditions, in the order an answer stops being available:

| Asked about | Fact requires | Otherwise |
| --- | --- | --- |
| The receiver | Stage 4's rule: a simple name nothing in scope binds, in a class without supertypes, outside a class body declared in a method, resolving through `resolveType` to one current top-level class inside the ADR 008 root | Stage 4's reason families |
| The target class | declares no supertypes | `declares supertypes, so a method of this name it may inherit, or hide, could be the target` |
| The method name | exactly one declared method of it | `declares no method of this name` / `declares {n} methods of this name, and overloads are not resolved` |
| That method | `static` | `is not static, so naming it through the class is not a call Java compiles` |
| Its access | public, or any access when the class is the one enclosing the call | `is {access}, which is outside the access this frontend resolves across classes` |

The access rule is where the two halves of "same unit" stop being the same
thing: a class reaches its own private members, and another top-level class in
the same file is as far away as one in another module. `Local.own()` is a fact,
`Companion.secret()` from `Local` is not, and both are written in one unit.

### Where The Candidates Come From, And Why They Are Small

A unit is analyzed from its own source, so the modifiers of a class it does not
declare reach it as the extension labels Stage 3 put on the graph. The analyzer
reads them for the names the unit actually writes:

1. `staticCallReceivers` reads every `Name.method(...)` the unit writes — a
   lexical pre-pass, not a decision, so it is deliberately a superset of the
   receivers that turn out to be classes.
2. Each pair is recorded as read, before anything is resolved. The reader that
   most needs reaching later is the one whose call resolves to nothing today.
3. `membersFor` resolves each distinct receiver name the way the frontend will —
   a single-type import before the unit's own package — and carries back only
   the methods of the invoked names, overloads included.

So the table the frontend selects from is the size of the question, not the size
of the provider or of the package. Measured as an assertion rather than claimed:

| Repository | Candidates examined for one `Util.make()` |
| --- | ---: |
| The provider and the caller | **1** |
| Plus 20 more classes in the same package, each declaring `make` and `keep` | **1** |

Falsified by carrying the class's whole method list instead of the invoked
name's: the same assertion fails at 2, and keeps failing as the package grows.

A receiver naming a class of the analyzed unit needs none of this: both ends are
in one batch, so the modifiers are the ones this analysis just read.

### Two Channels, And Which One Earns Its Keep

A resolved call declares a dependency on the provider unit. An unresolved one
cannot — it read nothing — so it is reached by the Stage 3 hint on the pair it
wrote. The measurements say what each buys, over four Java units sharing one
package scope:

| Change to the provider | Reanalyses | Reached by |
| --- | ---: | --- |
| A method body, while the call resolves | 1 | the dependency — which is per unit, not per method |
| `public` dropped from the invoked method | 1 | dependency, then the fact is gone and so is the dependency |
| `static` dropped, overload added, method removed | 1 each | the hint alone: 0 dependencies in the graph |
| The method appears where the reader found none | 1 | the hint alone, then the fact declares the dependency again |
| Provider moved out of the caller's source root | 1 | the dependency |

The sibling declarer and the importer are never among them. The first row is the
honest cost of a cross-unit fact: a dependency names a unit, so an edit to any
part of that unit re-reads its callers. The rows with no dependency at all are
what the aspect channel exists for, and Stage 3 proved them with seeded hints
that Stage 5 now makes real.

This also closes Stage 4's residual risk. A provider renamed out of the caller's
root used to leave the caller's answer stale, because nothing reached it; it now
declares a dependency, so the rename reanalyzes it and the call goes back to
`none in a Java source root this unit can see`.

### What The Stage 3 Tests Had To Become

Two of them were written against a world where nothing populated hints, and
Stage 5 is exactly the change that ends it. They were rewritten rather than
relaxed:

- *a hinted reader is reanalyzed…* seeded a hint by hand and asserted that no
  dependency existed. The reader now hints itself, and its resolved call
  declares a dependency, so the test asserts the split instead: which re-reads
  the dependency causes, which the hint causes, and the count of declarations at
  each step.
- *an unhinted reader is not reached…* can no longer have an unhinted reader.
  The claim that survives — a hint a unit has outgrown costs a pass and no claim
  — is now made with the sibling, which reads nothing of the provider and is
  hinted anyway. It is re-read, says what it said before, and the only claim
  that moves is the real reader's.

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the semidx target |
| `zig fmt --check build.zig src tests` | Clean |
| `zig build test-core` | 97/98 passed, 1 skipped |
| `zig build test` | 249/251 passed, 2 skipped — from 248/250, the new work-bound test |
| `zig build test-mcp` | 30/31 passed, 1 skipped |
| `zig build dogfood` | Exit 0 |
| `zig build preview-gate` | Exit 0, 14/14 steps, 6/6 tests, 28 hard passes |
| Falsification: carry every method of the class | The work-bound test fails at 2 candidates instead of 1 |

Propagation: the hint-only re-reads spend **0** rounds, because there is nothing
in the graph to walk; a dependency re-read spends **2** — one to reach the
dependent, one to find it leads nowhere further. Nothing exhausted its budget in
any lane.

The frontend's `coverage_note` changed with the behavior, because it is an
MCP-visible statement of what resolves and it would otherwise be false. The
capability matrix, `SPEC.md`'s coverage wording, and the external remeasurement
against the 135 are Stage 7's.

### Residual Risk

- **A dependency is per unit.** Any edit to a provider re-reads every caller
  that resolved into it, including edits no caller can observe. Narrowing that
  would mean per-entity dependencies, which is not this plan's to introduce; the
  first row of the table above is the measurement a future plan would start
  from.
- **`membersFor` walks the provider unit once per distinct receiver class.** It
  is bucketed per unit and so costs what the provider holds, not what the
  repository holds, but it is new index-path work proportional to distinct
  receiver classes per unit. Stage 7 measures it externally.
- **Hints are keyed by the name as written**, so a class of the same name in an
  unrelated module still over-invalidates — Stage 3's accepted trade, now with
  real hints behind it rather than seeded ones.
- **The reason strings are formatted per call.** Stage 4 recorded the growth;
  Stage 5 adds the target-side families, so the measurement Stage 7 owes now
  covers both.

## Stage 6: Follow-Up Discipline

Both deferred subsets were re-measured against the implementation rather than
argued about. Neither moved.

### Method

Stage 0 classified its sample offline, by modelling the frontend's rules over
parsed source. Stage 5 made the model unnecessary: the behavior exists, so this
stage measures it directly, and measures the whole graph rather than a sample.

- Repository: the same clone, `apache/dubbo` at `df9c5e1`, 4,050 Java units,
  cached outside this repository. No network was used.
- Two binaries over the same input, both `ReleaseFast`: the Stage 4 commit
  `384507e` (before static call facts) and the Stage 5 commit `8a1f083` (after).
  The Stage 4 tree was extracted with `git archive` into a scratch directory, so
  no branch, worktree, or checkout in this repository was touched.
- Both runs used `zig build run -- <clone>`, the developer inspection command,
  which prints graph totals and every unresolved target with its explanation.
  Unresolved targets were counted by reason family with a script kept in the
  scratch directory; the families are the explanation fragments the frontend
  emits, so the classification is the frontend's own vocabulary rather than a
  second model of it.
- Both runs are deterministic: repeating the after-run reproduced its totals
  exactly.

The Stage 4 run reproduces Stage 0's whole-graph numbers to the unit —
definitions 26,509, assertions 230,753, facts 90,439, unresolved 140,314,
approximate 0 — so the baseline this stage compares against is the recorded one
and not a new one.

### What Moved

| Unresolved call family | Before | After | Delta |
| --- | ---: | ---: | ---: |
| Receiver is a simple name a binding introducer declares | 55,127 | 55,127 | 0 |
| Receiver is not a simple name | 21,132 | 21,132 | 0 |
| Receiver name does not resolve to a class | 14,171 | 14,171 | 0 |
| Unqualified: no method of this name in the enclosing class | 13,707 | 13,707 | 0 |
| Receiver name blocked by the enclosing class's supertypes | 6,206 | 6,206 | 0 |
| Unqualified: enclosing class has supertypes | 4,049 | 4,049 | 0 |
| **Receiver names a class, target undecided** | **3,930** | **0** | **−3,930** |
| Unqualified: overloaded | 1,417 | 1,417 | 0 |
| Receiver inside a class body declared in the method | 629 | 629 | 0 |
| Unqualified: inside a class body declared in the method | 195 | 195 | 0 |
| **Target: overloaded** | 0 | 887 | +887 |
| **Target: class declares supertypes** | 0 | 777 | +777 |
| **Target: outside the covered access** | 0 | 52 | +52 |
| Total unresolved calls | 120,563 | 118,349 | −2,214 |
| Total unresolved references | 19,751 | 19,751 | 0 |

Every reference bucket is identical too, each one of the twelve, to the unit.

So the whole of the change is one row: of the 3,930 calls whose receiver names a
class the graph can answer for, **2,214 became `CALLS` facts** (56.3%) and 1,716
stayed unresolved for a target-side reason. Nothing else in the graph moved.

Two target-side families are **empty**, which is the useful kind of zero: a
missing method and a non-static method reached through a class name are calls
Java would not compile, so real source does not contain them. The rule's
declines are all cases the language does permit and this frontend does not
resolve.

### What The Follow-Ups Now Carry

- [Follow-up 014](../followups/014_java_instance_receiver_calls.md) owns value
  receivers: 55,127 bound simple names plus 21,132 receivers that are not simple
  names, unchanged to the unit. The static rule cannot reach them — a bound name
  is declined by the obscuring rule and a non-simple name before it — so the
  subset is unchanged rather than merely no larger. Its sampled addressable
  figure of 63 stands.
- [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md) owns the
  supertype guard: 8,083 references and 6,206 call receivers blocked by it,
  unchanged to the unit. Its sampled convertibility figures — 38 convertible, 13
  safely — stand, because no reference rule moved.

Neither follow-up was implemented, and neither grew.

### One Delta This Stage Did Not Explain

Current facts rose by **2,320** while current unresolved fell by **2,214**, and
recorded assertions rose by **106**. The 2,214 is fully accounted for by the
table above. The remaining 106 facts are assertion records that did not exist
before rather than conversions of records that did.

What is ruled out by measurement: it is not nondeterminism (the run repeats
exactly), not diagnostics (59,022 in both), not entity churn (26,509 definitions
in both), not references (every bucket identical), and not stale assertions
(zero in both). It does not appear at module scale: `dubbo-common` alone gives
+1,402 facts, −1,402 unresolved and **no** change in recorded assertions, so it
is tied to reanalysis across the whole batch rather than to the rule itself.

What it is, this stage does not know, and it is recorded rather than explained
away. It is 0.05% of the graph and no unresolved claim is missing because of it,
but Stage 7 owns the full external probe and should account for it there.

### Verification

| Command | Result |
| --- | --- |
| `zig build run -Doptimize=ReleaseFast -- <clone>` at `384507e` | 26,509 definitions, 230,753 assertions, 90,439 facts, 140,314 unresolved — Stage 0's baseline reproduced exactly |
| The same at `8a1f083` | 26,509 definitions, 230,859 assertions, 92,759 facts, 138,100 unresolved |
| The same, repeated | Identical totals |
| The same over `dubbo-common` only, both binaries | +1,402 facts, −1,402 unresolved, assertions unchanged |

No local lane changed in this stage, and no committed test depends on the
external clone.

### Residual Risk

- **The comparison is whole-graph, and Stage 7's bar is sampled.** This stage
  answers its own question — did either follow-up's subset move — which the
  whole graph answers better than a sample. The plan's 135-invocation threshold
  is stated against Stage 0's 1,200-definition sample, and Stage 7 must
  re-derive that sample to answer it. The whole-graph conversion of 2,214 is
  evidence that the bar is reachable, not evidence that it is met.
- **The 106-assertion delta is unexplained**, as recorded above.
- **The classification script is not committed**, in keeping with this plan's
  rule that external measurements are evidence rather than conformance. What it
  does is a count of explanation fragments, and the fragments are named in this
  log, so it is rebuildable from what is written here.

## Stage 7: External Remeasurement, Documentation, And Closure

The plan's own bar is met: **139** of the sample's receiver-qualified unresolved
calls became exact `CALLS` facts, against a required floor of 100 and a Stage 0
prediction of 135.

### The Sample Is The Same Sample

Stage 0's harness was not kept, which Stage 6 had to work around. Stage 7
rebuilt it and got the sample back: 1,200 of the 26,509 Java definitions drawn
with seed `20260918`, then `semidx_references outgoing` for each. Run against
the pre-Plan-012 code it reproduces Stage 0's table to the unit.

| Sampled claim | Stage 0 | Stage 7 baseline run | Stage 7 current |
| --- | ---: | ---: | ---: |
| Outgoing claims | 6,710 | 6,710 | 6,710 |
| `calls` unresolved | 5,662 | 5,662 | **5,523** |
| `calls` fact | 174 | 174 | **313** |
| `references` unresolved | 804 | 804 | 804 |
| `references` fact | 70 | 70 | 70 |

So the comparison below is like-for-like and not a re-derivation: same
repository (`apache/dubbo` at `df9c5e1`), same commit, same 1,200 definitions,
same protocol, one process per run.

### The One Reason That Became Seven And A Fact

Stage 0's single explanation for 4,624 sampled calls — "qualified by a receiver
this frontend does not resolve" — now decomposes exactly:

| What the sample says now | Count |
| --- | ---: |
| **Resolved: `CALLS` fact naming a declared `static` method** | **139** |
| Receiver is a simple name a binding introducer declares | 2,554 |
| Receiver is not a simple name | 958 |
| Receiver name reaches no current class in scope | 555 |
| Enclosing class has supertypes, so an inherited field could obscure the name | 262 |
| Target class declares supertypes | 45 |
| Target method is overloaded | 57 |
| Invocation inside a class body declared in the method | 54 |
| **Total** | **4,624** |

The parts sum to the whole, which is the check that the decomposition is a
decomposition and not an estimate. Every other reason family is unchanged:
unqualified no-method 698, unqualified supertypes 231, unqualified overloads
104, nested 5 — each identical to Stage 0. References did not move at all.

Two families that exist in the rule are **empty in real source**: no call
declined for a missing method and none for a non-static method. Through a class
name, both are code Java would not compile.

### The Accepted-Access Denominator

ADR 009 accepts public targets plus any access when the target class is the one
enclosing the invocation. Both counts were measured rather than assumed: every
one of the 139 facts was followed to its target and its labels read.

| Measurement | Count |
| --- | ---: |
| Static-call facts in the sample | 139 |
| Of those, target is `public` and `static` | **139** |
| Of those, target is in the same unit as the caller | 0 |
| Distinct target methods | 56 |

So the public lower bound and the accepted-access count are the same number
here, and the plan's 80% bar is met at 103% of the Stage 0 prediction of 135.
The same-class case contributes nothing in this repository, which is a fact
about dubbo rather than about the rule.

### What It Costs

Both build modes, same machine, same clone, cold index measured from process
start to the first answered call:

| Measurement | Baseline | Current | Change |
| --- | ---: | ---: | --- |
| Cold index, ReleaseFast | 4.87 s | 5.75 s | +18% |
| Cold index, Debug | 41.48 s | 73.27 s | +77% |
| Peak RSS, ReleaseFast | 186.1 MB | 184.7 MB | −0.8% |
| Peak RSS, Debug | 285.9 MB | 281.5 MB | −1.5% |

Memory did not move: the class-shape labels and the member projection cost
nothing measurable against the Stage 0 baseline of 186 MB, which this run
reproduces exactly. Index time did move, and Debug moved most — the receiver
pre-pass, the member projection, and the reanalyses the new channels cause are
all on the index path.

Refresh, one file edited in a 4,050-unit repository:

| Edit to `StringUtils.java` | Baseline units analyzed | Current | Baseline | Current |
| --- | ---: | ---: | ---: | ---: |
| No-op refresh | 0 | 0 | 0.52 s | 0.54 s |
| A body edit no caller can see | 1 | **73** | 0.30 s | 0.46 s |
| One method loses `public` | 1 | **189** | 0.28 s | 0.73 s |
| The class gains a declared supertype | 1 | **363** | 0.28 s | 1.00 s |

This is the price of cross-unit facts, and it is the shape the plan asked for:
bounded by readers, not by the repository — 363 of 4,050 units at the widest.
The body-edit row is the honest part: a dependency names a *unit*, so an edit
that changes nothing a caller can see still re-reads its 72 callers. Propagation
never exhausted its budget in any run: `analysis_unavailable` is 0 in health
before and after.

### What Consumers See

| Habit-loop call | Baseline | Current |
| --- | --- | --- |
| `semidx_health` | 8 ms | 10 ms |
| `semidx_outline` (root) | 2.5 ms | 2.3 ms |
| `semidx_repo_map` (one package) | 27 ms | 21 ms |
| `semidx_find_definitions` | 3.7 ms | 3.5 ms |
| `semidx_references incoming` on `StringUtils.isNotEmpty` | 3.5 ms, **8** relationships | 2.9 ms, **49** relationships |
| `semidx_context depth=2` incoming on the same | 4.7 ms, 40,775 bytes | 4.8 ms, 69,967 bytes |

Latency did not regress anywhere; Plan 011's indexed access model still holds.
What changed is the size of the answers, because the edges now exist. Two
consequences the plan asked to be measured:

- **Bytes per Java definition item** rose from 1,829 to 1,996 (+9.1%), the cost
  of `java.access`, `java.static` and `java.supertypes` on every Java
  definition.
- **`semidx_context depth=2` now exhausts the default 32,000-byte budget** on a
  widely called static utility method, where the same call on the same
  repository did not before. Budget semantics did not change; what a budget fits
  did. `semidx_context` has no cursor, so the answer is to raise
  `max_response_bytes` or lower `depth`/`relationship_limit`, and the preview
  reference now says so.

### Documentation

| Document | What changed |
| --- | --- |
| [capability matrix](../spec/capability_matrix.md) | The Java definition-label row names the three class-shape labels and what `unknown` means; the relationship row states every ADR 009 condition; the unresolved row names each new reason family; "Not recorded" adds hiding, dispatch, overload selection, static imports and scoped receivers; the false-negative row is now about value receivers with their measured sizes; the evidence row carries this stage's numbers |
| [local preview](../mcp/local_preview.md) | A static-call paragraph with the exact covered case, the value receivers that stay unresolved, and the labels a definition carries; a budget note for the `semidx_context` exhaustion above |
| [SPEC.md](../../SPEC.md) | Names the second Java cross-unit producer, the labels that carry its evidence, and what it does not admit. The invalidation row already named the class-shape producer from Stage 3 |
| [GLOSSARY.md](../../GLOSSARY.md) | Unchanged and checked: `class shape` and `reader hint` already exist as project-wide concepts, and ADR 009's Java vocabulary — obscuring proof, binding introducer, covered access subset, static target — stays owned by the ADR and is not restated |
| [MEMORY.md](../../MEMORY.md) | Compressed to the current rule, its cost, and the two follow-ups |

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the semidx target |
| `zig fmt --check build.zig src tests` | Clean |
| `zig build test-core` | 97/98 passed, 1 skipped |
| `zig build test` | 249/251 passed, 2 skipped |
| `zig build test-mcp` | 30/31 passed, 1 skipped |
| `zig build dogfood` | Exit 0 |
| `zig build preview-gate` | Exit 0, 14/14 steps, 6/6 tests, 28 hard passes |
| External probe, 4 runs over 2 binaries and 2 build modes | Recorded above |

### Definition Of Done

| Requirement | State |
| --- | --- |
| External baseline and addressable subsets recorded | Stage 0 |
| ADR 009 accepted and followed by every later stage | Stage 1, and the fixture matrix is its executable form |
| At or above 100 exact facts in the Stage 0 sample | **139** |
| At least 80% of the accepted-access subset exact | 139 of 139 measured accepted-access targets; 103% of the Stage 0 prediction |
| A simple-name receiver is never read as a type where anything could obscure it | Stage 4, 13 binding-introducer cases plus the inherited-field and before-declaration cases |
| Unsupported, ambiguous, stale, out-of-scope, inaccessible, non-static, overloaded, obscured and open-hierarchy cases stay unresolved with distinct reasons | 49 fixture cases, and the external decomposition above |
| Instance receivers remain unresolved and tracked | [Follow-up 014](../followups/014_java_instance_receiver_calls.md), re-measured in Stage 6 |
| Provider method and class-shape changes maintain freshness incrementally | Stage 3 and Stage 5 edit tests; externally 73/189/363 units re-read per edit class |
| No query, write-path or propagation regression from Plan 011 | Latency table above; propagation never exhausted; per-invocation lookup is 1 candidate whether the package holds 2 classes or 22 |
| The supertype guard unchanged and owned by Follow-up 013 | Stage 6: 8,083 references and 6,206 receivers, unchanged to the unit |
| Capability docs and `MEMORY.md` describe the boundary honestly | This stage |
| Every stage's verification, skipped checks and residual risk recorded | This log |

**The plan is complete.**

### Residual Risk

- **A one-file refresh costs more than it did.** 0.28 s to 1.00 s at 4,050
  units, and up to 363 units re-read for a class-shape edit. Bounded by readers
  and measured, but a repository with a hub utility class and a much larger
  reader set will feel it. The narrowing available — per-entity dependencies
  instead of per-unit — is not this plan's to introduce.
- **Debug index time rose 77%.** ReleaseFast, which the preview reference tells
  a user to run, rose 18%. Nothing in the habit loop got slower.
- **`semidx_context depth=2` exhausts the default budget** on a hub method, as
  recorded. It is an honest truncation with `budget_exhausted: true`, not a
  silent one.
- **Stage 6's 106-assertion delta is still unexplained.** It did not change
  here: the health totals are the same ones. It remains 0.05% of the graph, with
  no unresolved claim missing because of it.
- **One repository is one repository.** Every external number here is dubbo's.
  A second sample may move the shares, and the classification harness is
  described well enough in this log to rebuild.

## Post-Closure Review (2026-09-20)

A deep review of the closed plan, run against `6a47ba5` on a clean tree. It read
`ADR 009`, the plan, this log, the capability matrix, the preview reference and
the final diff of Stages 3 to 7; re-ran every committed lane; and probed the
implementation where a claim could be falsified locally. It did not have the
external clone, so no number measured against `apache/dubbo` was re-derived.

Nothing here reopens the plan. Three findings went to the register; two of
those were then fixed, and the rest are recorded below with their disposition.

Finding 2 was the one that changed shape after the review. It was written up as
contrived and was then checked against `javac` 17, which showed the program
compiles and calls a different method of a different class than the fact names.
Fixing it costs recall that this repository cannot measure, and the capability
matrix records that against the 139 rather than leaving the number standing
unqualified.

### Findings

| # | Finding | Disposition |
| ---: | --- | --- |
| 1 | A moved unit is never reanalyzed, so a `CALLS` fact survives a move out of its provider's Java source root. Reproduced: `renamed=1 analyzed=0`, and the relationship stays a fact where the matrix asserts unresolved for a unit written at that path | **Fixed** — [Follow-up 015](../followups/015_unit_path_change_does_not_reanalyze.md) |
| 2 | `import static a.b.C.*;` poisons no name, because `importedName` returns null on `asterisk`, so an obscuring static-imported field can yield a false fact | **Fixed** — [Follow-up 016](../followups/016_java_static_call_rule_narrow_gaps.md) |
| 3 | `is_static` has no `unknown`, so a definition with no `java.static` label is reported as "is not static" — a claim about the source the graph does not hold | **Fixed** — [Follow-up 016](../followups/016_java_static_call_rule_narrow_gaps.md) |
| 4 | Two reason families in `externalStaticTarget` are unreachable while `membersFor` and `resolveType` agree on lookup order, and no fixture asserts them | **Fixed** — [Follow-up 016](../followups/016_java_static_call_rule_narrow_gaps.md) |
| 5 | Stage 7's decomposition names eight rows, but the rule can answer eleven families. Three are neither listed nor declared empty | Accepted, corrected below |
| 6 | The 106-assertion delta was assigned to Stage 7 by Stage 6 and closed as unexplained, with no owner afterwards | Deferred — [Follow-up 018](../followups/018_unexplained_assertion_delta.md), which now owns it |
| 7 | The rebuilt sampling and classification harness is again uncommitted, and the log records the seed but not how the seed selects the sample | Deferred — [Follow-up 017](../followups/017_plan_012_external_evidence_reproducibility.md) |
| 8 | The 80% bar is reported as "139 of 139 measured accepted-access targets", which is 100% by construction | Accepted, clarified below |
| 9 | [Follow-up 014](../followups/014_java_instance_receiver_calls.md)'s "Current Behavior" still carries Stage 0's 1,041 / 3,583 split, which Stage 7 superseded with 139 and 3,512 | Accepted, to be corrected when that entry is next touched |

### Correcting Finding 5

The rule can answer eleven reason families for a receiver-qualified invocation.
Stage 7's table lists eight and declares two more empty — "no such method" and
"non-static". The three it does not mention are `inaccessible`, "shape not
read", and "supertypes unknown". They are **zero**, and the evidence for that is
the sum rather than a separate count: the eight listed rows plus the 139 facts
total 4,624 exactly, so nothing was left in an unlisted family. The one worth
naming explicitly is `inaccessible`: no call in the sample reached a class-name
receiver whose single declared method of that name was package-private or
protected.

That is weaker evidence than a count, because it rests on the classifier having
a pattern for every family. It is enough to say the families are empty and not
enough to say they were measured.

### Clarifying Finding 8

The plan's bar is "at least 100 and at least 80% of the accepted-access measured
subset", with the Stage 0 addressable subset of 135 as the denominator to
recalculate if ADR 009 accepted more than public targets. The Definition of Done
row leads with "139 of 139", which is circular — the denominator there is the
set of targets the 139 facts point at. The substantive reading is the one beside
it: 139 against a recalculated denominator of 135 (the same-class case ADR 009
added contributes 0 in this repository), so the bar of 108 is met at 129% and
the floor of 100 at 139%. Both numbers are in the log; only the framing is
misleading.

### Hypotheses tested and rejected

Recorded because each would have been a serious defect and each is now ruled
out by evidence rather than by reading:

- *`membersFor` and `resolveType` could resolve one receiver name to different
  classes, making the fact name the wrong method.* Rejected: both look up a
  single-type import before the unit's own package, and a name the unit itself
  declares never reaches `membersFor`.
- *`changed_shapes` and `changed_packages` borrow class and method names from
  entities that reconciliation may remove mid-batch, so `finish` could read
  freed memory.* Rejected: `StringPool` is arena-backed and interns for the
  life of the graph; nothing is freed per entity.
- *`staticCallReceivers` returns `found.items` without `toOwnedSlice` and never
  deinitializes its seen-set, and `membersFor` does the same.* Rejected: both
  are handed the per-unit scratch arena `Analyzer.analyze` creates and drops.

### What the review could not check

- Every external number — 139 facts, the reason decomposition, index time, RSS,
  habit-loop latency, bytes per definition item — was taken as reported. No
  clone and no harness were available, which is Finding 7.
- Findings 2 and 3 are argued from the code and from JLS 6.4.2 and 7.5.4. No
  executable fixture reaches either; writing one is part of
  [Follow-up 016](../followups/016_java_static_call_rule_narrow_gaps.md).

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches the semidx target |
| `zig fmt --check build.zig src tests` | Clean |
| `zig build test-core` | Exit 0 |
| `zig build test` | Exit 0 |
| `zig build test-mcp` | Exit 0 |
| `zig build dogfood` | Exit 0 |
| `zig build preview-gate` | Exit 0, every hard pass reported |
| `./scripts/check-constitution-freeze.sh --commit 6a47ba5` | Exit 0; the seal matches `ARCHITECTURE_CONSTITUTION.md` |
| `./scripts/check-agent-attribution.sh --range 6a47ba5~5..6a47ba5` | Exit 0 |
| `./scripts/check-readme-stewardship.sh --all` | Exit 0 |
| `./scripts/check-memory-freshness.sh --range 6a47ba5~5..6a47ba5` | Exit 0 |
| Arithmetic re-checked | 2,554+958+555+262+57+45+54+139 = 4,624; 174+139 = 313; 5,662−139 = 5,523 |
| Finding 1 repro | Temporary test over the `Tree` fixture, run and reverted; the tree was left clean and `zig build test` re-run at exit 0 |

`zig build dogfood` and `zig build preview-gate` print `failed command:` lines
for their test runners while exiting 0. Why they do is not known here, and it is
worth resolving separately: a green lane that prints a failure line is a lane
whose logs cannot be read at a glance.
