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

No Java semantic code changed. The same measurement priced the alternatives, and
the plan now targets static `ClassName.method()` calls at **135** in the same
sample, which clears the same threshold with less machinery.
[ADR 009](../adr/009_java_static_calls.md) is accepted, the Stage 2 fixture
matrix states what it requires, and Stage 3 is next. See
[The Decision](#the-decision) and
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
| Stage 1: ADR for Java static calls | Completed | [ADR 009](../adr/009_java_static_calls.md) accepted: a class-name receiver resolves only when nothing can obscure it, the target class declares no supertypes, and the target is its one declared `static` method inside the covered access subset (public, plus any access inside the enclosing class). Rejected alternatives recorded: capitalization heuristic, method-only binding checks, admitting target classes with supertypes, widening access ahead of evidence, provider-source re-reading, a shared-core kind. |
| Stage 2: Java quality fixtures and counters | Completed | 47 cases in five tests state what ADR 009 requires before any behavior changes: the covered and declined static calls, every binding introducer that obscures a receiver name, the provider edit sequence, the value receivers that must stay unresolved, and the work counters. Falsified by flipping the matrix switch: the three behavioral tests fail exactly where Stage 5 must deliver. `zig build test` 238/240, from 233/235. |
| Stages 3-7 | Not started | Next: Stage 3 projection, class shape, and invalidation. |

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
