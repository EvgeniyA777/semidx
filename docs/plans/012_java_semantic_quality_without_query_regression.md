---
title: "Java semantic quality without query regression"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-19"
---

# 012: Java Semantic Quality Without Query Regression

## Goal

Increase the number of useful exact Java answers on an external-scale Java
repository without losing the graph-query speed Plan 011 just bought.

Plan 010 showed that Java's next value gap is no longer the source-root
boundary. It is semantic coverage: 4,624 of 5,662 sampled unresolved calls were
qualified by a receiver the frontend does not resolve, and 62% of sampled
in-working-copy unresolved references were declined by the supertype guard.
Plan 011 removed the known query-work bottleneck but did not re-run the external
apache/dubbo wall-clock probe. This plan joins those two facts: first prove the
habit loop is fast enough after Plan 011, then widen Java only where the
frontend can establish exact source-derived facts.

## Product Principle

When a choice is available, decide in this order:

1. **Exactness beats recall.** A new Java edge is useful only if it remains a
   fact under the constitution's distinction between fact, unresolved, and
   approximate assertion.
2. **The habit loop must stay usable.** A richer graph that makes
   `semidx_health` -> `semidx_outline` -> `semidx_repo_map` ->
   `semidx_find_definitions` -> `semidx_references` / `semidx_context` slow
   enough to abandon is a product regression.
3. **Java projections are not graph authority.** Package, source-root, receiver,
   member, and hierarchy lookup tables may find candidates. The graph records
   only the resulting assertion, its resolution, producer, evidence, freshness,
   and dependencies.
4. **Unresolved reasons are product output.** A negative answer must say whether
   the frontend lacked a receiver type, saw overloads, hit supertypes, crossed a
   source-root boundary, or found no source.
5. **No Java build system enters by accident.** Build descriptors, classpaths,
   modules, jars, and dependency graphs stay out unless a future plan and ADR
   admit them explicitly.

## Start Rule

Read before starting implementation:

- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  especially the external Java probe, unresolved-reason measurements, and
  residual risk.
- [Plan 011 progress](../reports/011_external_scale_graph_query_indexes_progress.md),
  especially the statement that external Java latency was not re-measured.
- [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) and
  [ADR 008](../adr/008_java_visibility_boundaries.md).
- [Follow-up 011](../followups/011_java_cross_module_visibility.md).
- `src/frontends/java.zig`, `src/frontends/java_packages.zig`,
  `src/frontends/root.zig`, and `src/root.zig`'s `Upkeep`.
- [Testing policy](../agent-policy/testing.md).

Run `./scripts/check-zig-version.sh` before code work. Create
`docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
with progress-log frontmatter before the first code change.

Stage 0 is a real go/no-go. Re-run the post-Plan-011 external Java speed and
quality baseline before changing Java semantics. Prefer the same apache/dubbo
commit used by Plan 010. If that root is unavailable, stop before code changes
and either make the external root available or amend this plan explicitly to
name a substitute repository. Do not infer a post-Plan-011 product latency from
Plan 011's synthetic work bound.

Stop and re-open Plan 011 or this plan before widening Java if Stage 0 or the
local Plan 011 scale lane shows that anchored relationship work again scales
with total assertions rather than with anchored candidates. If the external
MCP run cannot expose deterministic counters, record that limitation and run
the local work-bound lane before proceeding. Wall-clock timing is recorded as
an observation; the hard stop is a broken work bound, not a slow clock by
itself.

## Scope

- Re-measure the Plan 010 external Java habit-loop probe after Plan 011's query
  indexes.
- Add a deterministic Java semantic-quality fixture matrix for receiver calls,
  unresolved reasons, provider changes, and exact negative cases.
- Add Java analyzer-side projection(s) for current declared methods and the
  units that may read them.
- Add a conservative receiver type environment for Java method bodies.
- Resolve receiver-qualified Java calls only when the receiver type and target
  method are exactly established.
- Reassess the supertype guard after receiver work, and relax it only for a
  closed source-available hierarchy whose member-type shadowing has been ruled
  out.
- Update capability documentation, local preview coverage notes, `MEMORY.md`,
  and the progress log.

## Non-Scope

Do not read or execute Maven, Gradle, Bazel, `module-info.java`, jars, class
files, generated sources outside the indexed working copy, or any network
resource.

Do not close [Follow-up 011](../followups/011_java_cross_module_visibility.md)
or add cross-module visibility. The existing ADR 008 source-root boundary stays
in force.

Do not admit shared-core `module`, `IMPORTS`, package entities, classpath
entities, method-signature entities, or inheritance entities. If the work seems
to require one, stop and create the CORE/ADR input instead of smuggling it
through a Java plan.

Do not add approximate, name-match, text-search, vector, popularity, or
best-effort receiver resolution. A receiver-qualified call whose receiver type
or target method is not exactly established stays unresolved.

Do not change MCP tool JSON shape, tool arguments, cursor semantics,
response-budget semantics, `semantic_contract_version`, or the text fallback.
New Java facts surface through existing relationship, resolution, producer,
freshness, evidence, and diagnostic fields.

Do not add persistence, SQLite, a daemon, file watching, HTTP, or a public
contract. Query and write-path measurements stay over the current local
in-memory graph.

Do not claim broad Java support. Capability claims remain matrix-bound and must
state the exact covered cases and the cases deliberately left unresolved.

Do not change Clojure or Zig frontend semantics.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  sections 1, 3, 5, 6, 7, and 8.
- [MEMORY.md](../../MEMORY.md), for current implementation reality and known
  gaps.
- [ADR 003](../adr/003_reject_name_match_assertions.md), for rejecting
  repository-wide name matching as graph authority.
- [ADR 004](../adr/004_allow_java_same_package_type_resolution.md), for
  analyzer-side Java package projections and provider dependencies.
- [ADR 008](../adr/008_java_visibility_boundaries.md), for derived source-root
  visibility.
- [Follow-up 011](../followups/011_java_cross_module_visibility.md), for the
  explicit cross-module boundary left open.
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  for external Java quality evidence.
- [Plan 011 progress](../reports/011_external_scale_graph_query_indexes_progress.md),
  for query-index evidence and the unmeasured external-latency gap.
- [docs/spec/capability_matrix.md](../spec/capability_matrix.md), for supported
  language coverage wording.
- [docs/mcp/local_preview.md](../mcp/local_preview.md), for MCP preview coverage
  wording.

## Current Evidence

The current Java frontend records top-level class and method definitions, field
and method-return type references, same-source-root/single-type-import type
references, and very narrow same-class unqualified invocation facts.

Qualified calls are intentionally unresolved today. `emitInvocation` treats any
`method_invocation` with an `object` field as a designator carrying the full
invocation text, and `invocationTarget` returns the reason "the invocation is
qualified by a receiver this frontend does not resolve". On the Plan 010 sample,
that reason accounts for 4,624 of 5,662 unresolved calls.

The supertype guard is also deliberate. `resolveType` declines cross-unit simple
type resolution when the enclosing class declares a superclass or interfaces,
because an inherited member type could shadow the apparent target. On the Plan
010 sample, that guard accounts for 64 of 103 in-working-copy unresolved
references, or 62%.

The Java package table is the right precedent for this plan. It is an
analyzer-side projection, not a graph model; it keeps only hints, re-reads graph
facts before answering, and creates no package entity, module entity, or import
relationship. `Upkeep` reanalyzes providers, dependents, package declarers, and
single-type importers so cross-unit facts and unresolved-to-resolved transitions
stay maintainable.

Plan 011 proved anchored query work with synthetic local bounds past the size of
apache/dubbo, but it deliberately did not claim a new Dubbo wall-clock latency.
This plan cannot treat speed as already measured on the target adoption shape.

## Plan-Level Decisions

**D1 - Receiver facts require an exact static receiver type.** A qualified call
may become a `CALLS` fact only when the receiver expression has a statically
known Java class under the frontend's covered rules. Receiver expressions outside
the covered shapes keep their designator and an unresolved reason.

**D2 - Method lookup is an analyzer-side Java projection.** The method table is
rebuilt from current graph facts and Java source evidence. It may cache hints,
but every hinted class and method is re-read before use. It creates no graph
entity and has no authority beyond candidate selection.

**D3 - The source-root visibility boundary applies to methods too.** If a
receiver type resolves to a class outside the referring unit's ADR 008
visibility scope, the call is unresolved. A method in an out-of-scope class is
not a fact just because its name matches.

**D4 - A method target must be unique in the covered method set.** Because this
plan does not type arguments, overloads stay unresolved. Because inherited
methods can change dispatch, a target class with supertypes stays unresolved
until Stage 5 proves a closed exact hierarchy for that specific case.

**D5 - Incremental maintenance covers unresolved-to-resolved transitions.** A
unit whose call was unresolved because a known receiver class lacked a unique
method must be reachable when that receiver class later adds, removes, renames,
or overloads the method. A resolved cross-unit call must also declare provider
dependencies so provider edits invalidate callers.

**D6 - Speed regressions are measured as work first.** External wall-clock
numbers are recorded because users feel them, but acceptance relies on
deterministic work bounds and growth shape: receiver/member lookup must use
bounded candidate tables, not repository-wide scans in per-call paths.

**D7 - The supertype guard is not weakened by hope.** Stage 5 may relax it only
when all relevant supertypes are current source classes inside the visibility
boundary, no interface/unknown superclass keeps the hierarchy open, and member
type shadowing has been checked through the reachable hierarchy. Otherwise the
current unresolved answer remains correct and the stage records a follow-up.

**D8 - Public surfaces stay unchanged.** Better Java resolution changes graph
content, not MCP contracts. New outcomes appear as existing `fact` or
`unresolved` relationships with evidence and producer metadata.

## Architecture Boundaries

1. **Java frontend**
Responsibility: Java receiver/type evidence, local lexical scopes, Java method
candidates, and the rules that decide whether a Java relationship is a fact or
unresolved.
Does not know about: MCP payload shape, response budgets, storage backends, or
other frontends' semantics.

2. **Java analyzer projections**
Responsibility: candidate tables for packages, imports, methods, receiver
readers, and optional hierarchy evidence. Hints may be conservative supersets.
Does not know about: graph authority. A projection may find a candidate, but a
fact exists only when the frontend records it in the graph with exact evidence.

3. **Shared core**
Responsibility: entities, relationships, assertions, resolution categories,
freshness, identity, dependencies, and snapshots.
Does not know about: Java receiver scoping, Java packages, Java source roots,
method overloads, or inheritance.

4. **Incremental upkeep**
Responsibility: reanalyzing units affected by provider and projection changes.
Does not know about: choosing Java facts. It only preserves freshness and
dependency propagation.

5. **MCP preview**
Responsibility: projecting the graph as it exists.
Does not know about: this plan. Tool contracts do not change.

## Stages

### Stage 0: Post-Plan-011 External Baseline

Purpose: establish the speed and Java-quality baseline this plan must preserve
and improve.

Likely files:

- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`

Required behavior:

- Re-run the Plan 010 probe on apache/dubbo at the same commit when available,
  or on a substitute open-source Java repository named in the progress log with
  its commit, module/source-unit counts, and reason for substitution.
- Record the habit-loop calls used in Plan 010: `semidx_health`,
  `semidx_outline`, scoped `semidx_repo_map`, `semidx_find_definitions`,
  `semidx_references`, `semidx_context depth=1`, `semidx_context depth=2`,
  no-op refresh, and one-file refresh.
- Record wall clock, output size, source-unit counts, graph counts, diagnostic
  counts, and any deterministic work counters available from Plan 011's scale
  harness or MCP parity hooks.
- Re-run the same unresolved-reason sample shape as Plan 010, or record why the
  exact sample cannot be repeated. Split unresolved calls by receiver, overload,
  supertypes, nested class body, missing method, and other reasons. Split
  unresolved references by no-source, source-root boundary, imports, supertype
  guard, ambiguity, and unsupported construct.
- State whether the Plan 011 product claim is now supported by an external
  latency observation, still supported only by local work bounds, or contradicted
  by measured work.

Done when:

- The progress log records the repository identity, baseline commands, results,
  quality counts, and the go/no-go verdict against the Start Rule.
- No Java semantic code has changed before this verdict.

### Stage 1: Java Quality Fixtures And Counters

Purpose: make the exactness target executable before changing behavior.

Depends on: Stage 0 go.

Likely files:

- Java fixtures under the existing test/fixture layout.
- Java frontend tests in the existing Zig test lane.
- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`

Required behavior:

- Add committed fixture cases for receiver-qualified calls:
  - `this.m()` and `local.m()` to a unique declared method in a class with no
    supertypes;
  - parameter, local variable, field, and `new Type().m()` receiver shapes;
  - receiver type supplied by same unit, same source root, standard-layout
    test-to-main root, and single-type import;
  - unknown receiver, out-of-scope receiver class, duplicate local binding,
    overloads, target class with supertypes, nested class body, `super.m()`,
    `ClassName.staticLike()`, chained receivers, and unresolved receiver type.
- Add fixture cases for provider changes:
  - target method added after an unresolved call;
  - target method removed after a fact;
  - target method overloaded after a fact;
  - receiver class moved across the ADR 008 boundary.
- Add or expose test-only counters that let the lane compare call-resolution
  work and provider reanalysis work without relying on flaky timing thresholds.

Done when:

- The fixture matrix exists and currently records the old unresolved behavior
  where the implementation has not yet changed.
- Negative cases assert their unresolved reasons, not just "no fact".
- The progress log contains the stage's risk matrix update and focused command
  results.

### Stage 2: Java Method Projection And Invalidation

Purpose: add the candidate infrastructure needed for receiver calls, without
yet emitting new cross-unit call facts.

Depends on: Stage 1.

Likely files:

- `src/frontends/java.zig`
- `src/frontends/java_packages.zig` or a new `src/frontends/java_members.zig`
- `src/frontends/root.zig`
- `src/root.zig`
- focused tests/fixtures

Required behavior:

- Build a Java method projection from current graph facts and Java source
  evidence. At minimum, each current top-level Java class candidate carries:
  package, simple class name, class entity id, provider unit, source root,
  whether the class declares supertypes, and current declared methods grouped by
  simple method name.
- Keep projection storage as hints. Hints may grow and over-invalidate, but they
  must be re-read from the graph before answering.
- Preserve snapshot/query indexes from Plan 011. No relationship query path may
  scan every assertion to answer one receiver call.
- Add the reader-hint storage and `Upkeep` path that Stage 4 will populate for
  units that mention an exact receiver class and method name. The path must
  cover calls that are currently unresolved because the method is missing,
  overloaded, or blocked by supertypes.
- Extend `Upkeep` so a class method-set change reanalyzes affected readers, even
  when the previous relationship had no provider dependency because it was
  unresolved.
- For resolved cross-unit method targets, declare provider dependencies so
  provider edits invalidate callers.

Done when:

- Projection tests prove method-set lookup, uniqueness/overload classification,
  source-root visibility, stale-provider rejection, and reader invalidation
  through seeded reader hints.
- Existing Java package/import tests still pass unchanged.
- No new Java call fact is emitted by this stage except incidental same-class
  behavior already present before the stage.

### Stage 3: Exact Receiver Type Environment

Purpose: let the Java frontend know enough local static receiver types to make
Stage 4 possible.

Depends on: Stage 2.

Likely files:

- `src/frontends/java.zig`
- focused tests/fixtures

Required behavior:

- Build a method-body receiver environment with lexical scoping. Supported
  bindings must be explicit and limited:
  - `this` as the enclosing class;
  - formal parameters with simple class types that `resolveType` establishes as
    facts;
  - local variable declarations with simple class types, visible only after
    declaration and inside their lexical scope;
  - class fields with simple class types, consulted only when not shadowed by a
    parameter or local;
  - `new Type(...)` receiver expressions where `Type` resolves as an exact
    class under existing Java type rules.
- Treat duplicate declarations in the same lexical scope, malformed declarations,
  generic/array/wildcard receiver types outside the covered shape, assignments,
  casts, method-return receivers, chained field access, `super`, class-name
  receivers, and lambda/local-class body interactions as unresolved.
- Keep nested class bodies as a boundary. A call inside a class body declared
  within a method is still analyzed as nested and does not borrow the outer
  method's receiver environment.
- Record distinct unresolved reasons for "receiver type unknown", "receiver type
  ambiguous", "receiver type out of scope", and "receiver expression outside
  covered shapes".

Done when:

- The type environment can be tested without emitting receiver-qualified call
  facts.
- Fixture cases prove lexical shadowing, before-declaration use, duplicate
  bindings, field fallback, and source-root visibility.

### Stage 4: Receiver-Qualified Call Facts

Purpose: convert the measured receiver gap into exact Java `CALLS` facts where
the frontend has enough evidence.

Depends on: Stage 3.

Likely files:

- `src/frontends/java.zig`
- Java member projection files from Stage 2
- focused tests/fixtures

Required behavior:

- Resolve a receiver-qualified invocation to a fact only when all of these hold:
  - the receiver type environment establishes exactly one current Java class;
  - the class is inside the ADR 008 visibility boundary;
  - the method projection finds exactly one current declared method of that name
    in the target class;
  - the target class has no supertypes;
  - the invocation is not inside a nested class body;
  - no overload or unsupported receiver shape could change the target.
- Keep the full invocation text as the designator for unresolved qualified
  calls, as today.
- Declare provider dependencies for external receiver type and method provider
  units.
- Populate method reader hints for exact receiver class and method-name pairs,
  including unresolved calls that could become facts after a provider method-set
  change.
- Record distinct unresolved reasons for missing method, overloaded method,
  target class has supertypes, receiver out of scope, and unsupported receiver
  expression.
- Re-run Stage 1 fixtures with expected facts enabled for covered positive
  cases and expected unresolved reasons for every negative case.

Done when:

- Covered receiver-qualified calls become `CALLS` facts in committed fixtures.
- Every negative case remains unresolved with an exact reason.
- A provider method add/remove/overload edit reanalyzes the caller and changes
  only the affected claim.
- Focused counters show lookup work bounded by candidate tables, not by all
  Java units or all graph assertions per invocation.

### Stage 5: Supertype Guard Reassessment

Purpose: decide whether this plan can safely reduce the supertype-driven
reference gap after receiver calls land.

Depends on: Stage 4.

Likely files:

- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
- optional Java projection/frontend files if the exact subset below is admitted
- optional follow-up under `docs/followups/`

Required behavior:

- Re-run the Stage 0 unresolved-reference sample after Stage 4. Record whether
  the supertype guard is still the dominant in-working-copy reference gap and
  give concrete examples.
- If the remaining gap is not worth this plan's risk, record that decision and
  create a follow-up instead of changing the guard.
- If implemented, the only allowed relaxation is this closed exact subset:
  - every superclass in the chain resolves to a current Java class inside the
    ADR 008 visibility boundary;
  - no interface or unknown/non-class supertype keeps the hierarchy open;
  - cycles are detected and treated as unresolved;
  - member type declarations with the referenced name are checked through the
    reachable hierarchy;
  - any unsupported member type, missing provider, stale provider, or out-of-
    scope provider keeps the current unresolved answer.
- Do not add virtual dispatch, inherited method call resolution, interface
  semantics, or classpath lookup as part of this stage.

Done when either:

- The closed hierarchy subset is implemented with positive and negative tests,
  provider invalidation, and work-bound measurements; or
- The progress log records why the supertype guard stays unchanged and links a
  follow-up with exact acceptance direction.

### Stage 6: External Remeasurement, Documentation, And Closure

Purpose: prove the plan improved exact Java answers without query regression,
and leave the project documents aligned.

Depends on: Stage 4 and, if executed, Stage 5.

Likely files:

- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
- [docs/spec/capability_matrix.md](../spec/capability_matrix.md)
- [docs/mcp/local_preview.md](../mcp/local_preview.md)
- [MEMORY.md](../../MEMORY.md)
- this plan document
- optional follow-ups

Required behavior:

- Re-run the Stage 0 external probe and compare:
  - exact call facts and unresolved reasons;
  - exact reference facts and unresolved reasons;
  - `semidx_health`, `semidx_references`, and `semidx_context depth=2` work
    shape and wall-clock observations;
  - cold index, no-op refresh, one-file refresh, and provider-method-change
    refresh work;
  - memory impact of new projection tables where measured.
- Update the capability matrix and preview reference with the exact covered Java
  receiver cases and the cases left unresolved.
- Update `MEMORY.md` by compression, not by appending a progress log.
- Mark the plan and progress log complete only after verification evidence and
  residual risk are recorded.

Done when:

- The external remeasurement shows more exact Java receiver call facts in the
  covered cases.
- No new approximate assertions are introduced.
- Plan 011's anchored query work bound still holds.
- Documentation states the exact capability boundary without broad Java claims.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Receiver-qualified facts are exact | False `CALLS` facts from guessed receiver or method target | Java fixture/golden plus frontend integration | Covered receiver shapes resolve to one current method | Unknown receiver, overload, supertypes, out-of-scope type, nested class body | Stage 4 fixture tests and progress-log counts |
| Unresolved remains distinguishable | Lost reason detail makes unsupported, unavailable, and ambiguous cases look alike | Fixture/golden | Each decline reason appears in graph output | No-source, out-of-scope, overloaded, duplicate local, unsupported receiver | Stage 1 and Stage 4 negative fixtures |
| Incremental freshness holds | Caller stays stale after provider method add/remove/overload | Focused integration/edit-history test | Provider method-set change reanalyzes affected readers | Previously unresolved call becomes resolved; fact becomes unresolved | Stage 2/4 edit tests |
| Query speed is preserved | Per-call lookup scans all units/assertions | Test-only work counters plus external observation | Candidate work grows with receiver/method candidates, not repository size | Old full-scan path fails the bound | Stage 0/4/6 work measurements |
| Write path stays bounded | Method reader hints cause repository-wide reanalysis | Synthetic doubled-corpus integration test | Provider-method change reanalyzes readers, not all units | Unit stops reading a method but remains hinted as harmless superset | Stage 2/6 refresh measurements |
| Source-root boundary remains intact | Receiver/type/method lookup crosses modules by name | Fixture/golden | Same root and test-to-main resolve; other roots unresolved | Cross-module same package with no admitted dependency | ADR 008 fixtures reused in Stage 2/4 |
| Public contracts unchanged | MCP clients see shape drift | MCP tests/runtime smoke | Existing tool schemas and payload families still pass | New Java facts through existing relationship fields only | `zig build test-mcp`, `zig build preview-gate` |
| Capability docs stay honest | README/spec implies broad Java method resolution | Documentation review | Matrix names exact receiver cases and exclusions | Cross-module, overload, unknown hierarchy, classpath left unresolved | Stage 6 doc diff |

## Verification

Use the narrowest meaningful command first, then widen:

- `./scripts/check-zig-version.sh`
- `zig fmt --check build.zig src tests`
- focused Java frontend tests named in the progress log
- `zig build test-core` for shared graph/projection work that does not require
  parsers
- `zig build test` before each implementation-stage commit that touches Java
  frontend behavior, fixtures, or incremental upkeep
- `zig build test-mcp` when MCP-visible graph output is changed
- `zig build dogfood` and `zig build preview-gate` before closure
- `zig build test-core -Doptimize=ReleaseFast` for final scale/work-bound proof
  if the stage adds or changes scale counters

External repository measurements are evidence, not committed conformance. Pin
the repository and commit in the progress log, do not commit its source, and do
not make network access part of a required local lane.

## Drift Control

Before implementation, check this plan against `RULES.md`, the architecture
constitution, ADR 004, ADR 008, Follow-up 011, Plan 010 progress, Plan 011
progress, `MEMORY.md`, the capability matrix, and the current Java frontend.

During closure:

- If a new durable decision changes Java semantics beyond this plan's decisions,
  write or revise an ADR instead of burying it in the progress log.
- If a shared-core kind starts to look necessary, stop and route it through
  `CORE.md` and a future plan.
- Keep README out of this unless public positioning or quick-start behavior
  changes. Stage evidence belongs in the progress log.
- Keep `MEMORY.md` below its policy limit by replacing stale near-term text with
  links to the plan and progress log.

## Definition Of Done

This plan is complete when:

- the post-Plan-011 external Java baseline is recorded;
- receiver-qualified calls in the covered subset become exact facts;
- unsupported, ambiguous, stale, out-of-scope, overloaded, and open-hierarchy
  cases remain unresolved with distinct reasons;
- provider method changes maintain freshness incrementally;
- query and write-path work bounds show no regression from Plan 011's indexed
  access model;
- capability docs and `MEMORY.md` describe the new Java boundary honestly; and
- every stage's verification, skipped checks, and residual risk are recorded in
  the progress log.
