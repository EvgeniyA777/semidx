---
title: "Java semantic quality without query regression progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-19"
---

# 012: Java Semantic Quality Without Query Regression Progress

Companion log for
[docs/plans/012_java_semantic_quality_without_query_regression.md](../plans/012_java_semantic_quality_without_query_regression.md).

## Current Status

**Stage 0 is complete. Its verdict on the plan's original subject was no-go, and
the plan was amended rather than abandoned.** The Start Rule requires two things
before any ADR or code work; the first held and the second did not.

- The local Plan 011 work-bound lane still passes, so anchored relationship work
  still scales with anchored candidates.
- The external Java sample contains **63** public-method addressable
  receiver-qualified invocations against a required threshold of **100**.

No Java semantic code changed and ADR 009 was not written. The same measurement
priced the alternatives, and the plan now targets static `ClassName.method()`
calls at **135** in the same sample, which clears the same threshold with less
machinery. See [The Decision](#the-decision) and
[Amendment 1](../plans/012_java_semantic_quality_without_query_regression.md#amendment-1-from-instance-receivers-to-static-calls).

Stage 0 also settles the question Plan 011 deliberately left open: the external
latency observation now exists, and it supports the Plan 011 product claim
strongly. `semidx_context depth=2` on apache/dubbo fell from **90.71 s to
0.019 s** in the same build mode on the same repository and commit.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Post-Plan-011 external baseline and addressability gate | Completed | apache/dubbo re-probed at the Plan 010 commit. Habit-loop latency is no longer a product problem: the worst call fell from 90.71 s to 0.019 s. Quality is unchanged: 244 of 6,710 sampled outgoing claims are facts, and 4,624 of 5,662 unresolved calls are still receiver-qualified. The addressable public-method subset is 63, below the go threshold of 100. **Verdict: no-go.** |
| Stage 0 closure: Amendment 1 | Completed | Plan re-aimed at static `ClassName.method()` calls (135 in the sample). Instance receivers deferred to [Follow-up 014](../followups/014_java_instance_receiver_calls.md), the supertype guard to [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md). No code changed. |
| Stage 1: ADR for Java static calls | Not started | Next. |
| Stages 2-7 | Not started | Depend on Stage 1. |

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

### Verification

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
