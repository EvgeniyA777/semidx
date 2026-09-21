---
title: "Java semantic quality without query regression"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-19"
---

# 012: Java Semantic Quality Without Query Regression

**Completed 2026-09-19.** Every stage is executed and the Definition of Done is
met: in the Stage 0 sample, 139 receiver-qualified unresolved calls became exact
`CALLS` facts against a floor of 100 and this plan's own prediction of 135, with
no query regression and no approximate assertion. The evidence, the costs, and
the residual risk are in
[the progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md#stage-7-external-remeasurement-documentation-and-closure).

**Amended after Stage 0.** This plan originally widened Java toward
receiver-qualified instance calls. Its own Stage 0 gate measured that subset at
63 addressable public-method invocations against a required 100 and stopped the
plan. The same measurement priced the alternatives on the same sample, and this
plan is now aimed at the one that clears the gate with less machinery: static
`ClassName.method()` calls, worth 135. See
[Amendment 1](#amendment-1-from-instance-receivers-to-static-calls) and
[the progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md).

## Goal

Increase exact Java impact answers on an external-scale Java repository without
losing the graph-query speed Plan 011 bought.

Plan 010 showed that Java's next value gap is semantic coverage, not the
source-root boundary: in its external sample 4,624 of 5,662 unresolved calls
were qualified by a receiver the frontend did not resolve. Stage 0 of this plan
took that bucket apart. **1,041 of those 4,624 qualified receivers are class
names, not values** — `StringUtils.isNotEmpty(...)`, `CollectionUtils.isEmptyMap(...)`,
`NetUtils.getLocalHost()` — and 135 of them resolve exactly today under rules the
frontend already has. That is more than twice the instance-receiver subset, and
it needs no method-body type environment at all, because a class name is
resolved by the existing `resolveType`, not by inferring the type of an
expression.

Stage 0 also settled the speed question this plan exists to protect: the habit
loop is no longer slow on external Java. `semidx_context depth=2` on apache/dubbo
fell from 90.71 s to 0.019 s in the comparable build mode.

## Amendment 1: From Instance Receivers To Static Calls

Recorded 2026-09-19, after Stage 0 and before any ADR or code change.

| | Before | After |
| --- | --- | --- |
| Subject | receiver-qualified instance calls (`local.m()`, `field.m()`, `new T().m()`) | static calls (`ClassName.m()`) |
| Measured exact subset in the Stage 0 sample | 63 public | **135 public** |
| Receiver evidence needed | a lexical receiver **type** environment over method bodies | **no type environment**: the existing `resolveType`, plus proof that the name is not obscured by a binding |
| Stage 4 | build the type environment | prove the receiver name is not bound |
| Instance receivers | this plan's subject | non-scope, recorded as [Follow-up 014](../followups/014_java_instance_receiver_calls.md) |
| Supertype guard | measured for a possible follow-up | measured and deferred as [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md) |

What did not change: the exactness rule, the ADR-before-implementation gate, the
source-root boundary, the projection discipline, the invalidation requirements,
the query-work budget, and the prohibition on build descriptors, shared-core
kinds, approximate assertions, and MCP contract changes.

Why not the alternatives Stage 0 priced: admitting target classes that declare
supertypes would be worth 211, but of 210 such hierarchies re-derived from the
sample **none** is closed in indexed source, so the target could not be
established and the fact would be a guess. Lifting the supertype guard on the
referring class would convert 38 of 335 guarded references, only 13 of them
safely — below this plan's own follow-up threshold, which is why it leaves as a
follow-up rather than a stage.

## Product Principle

When a choice is available, decide in this order:

1. **Exactness beats recall.** A new Java edge is useful only if it remains a
   fact under the constitution's distinction between fact, unresolved, and
   approximate assertion.
2. **The habit loop must stay usable.** A richer graph that makes
   `semidx_health` -> `semidx_outline` -> `semidx_repo_map` ->
   `semidx_find_definitions` -> `semidx_references` / `semidx_context` slow
   enough to abandon is a product regression.
3. **Durable semantics need an ADR.** Cross-unit static Java `CALLS` facts are
   new language semantics. This plan may propose them, but implementation waits
   for an accepted ADR that answers the constitutional decision test.
4. **Java projections are not graph authority.** Package, source-root, method,
   and class-shape lookup tables may find candidates. The graph records only the
   resulting assertion, its resolution, producer, evidence, freshness, and
   dependencies.
5. **Unresolved reasons are product output.** A negative answer must say whether
   the frontend could not read the receiver as a type, found the name obscured by
   a binding, saw overloads, found a non-static or inaccessible method, hit
   supertypes, crossed a source-root boundary, or found no source.
6. **No Java build system enters by accident.** Build descriptors, classpaths,
   modules, jars, and dependency graphs stay out unless a future plan and ADR
   admit them explicitly.

## Start Rule

Read before starting implementation:

- [Plan 012 progress](../reports/012_java_semantic_quality_without_query_regression_progress.md),
  which holds the Stage 0 baseline, the classification method, and every count
  this plan's thresholds refer to.
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  especially the external Java probe and unresolved-reason measurements.
- [Plan 011 progress](../reports/011_external_scale_graph_query_indexes_progress.md),
  for the indexed access model this plan must not regress.
- [ADR 003](../adr/003_reject_name_match_assertions.md),
  [ADR 004](../adr/004_allow_java_same_package_type_resolution.md),
  [ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md),
  [ADR 008](../adr/008_java_visibility_boundaries.md), and
  [ADR 009](../adr/009_java_static_calls.md), which this plan implements.
- [Follow-up 011](../followups/011_java_cross_module_visibility.md),
  [Follow-up 013](../followups/013_java_supertype_guard_relaxation.md), and
  [Follow-up 014](../followups/014_java_instance_receiver_calls.md).
- [SPEC.md](../../SPEC.md), [CORE.md](../../CORE.md), and
  [docs/spec/capability_matrix.md](../spec/capability_matrix.md).
- [Product adoption strategy](../design/002_product_adoption_strategy.md).
- `src/frontends/java.zig`, `src/frontends/java_packages.zig`,
  `src/frontends/root.zig`, `src/root.zig`'s `Upkeep`, and
  `src/core/dependencies.zig`.
- [Testing policy](../agent-policy/testing.md).

Run `./scripts/check-zig-version.sh` before code work. The progress log already
exists; update it per stage rather than creating a second one.

Before pushing any stage commit, either update `MEMORY.md` when current
implementation reality, priorities, or known gaps changed, or record in the
progress log why the memory entry is still accurate before using
`SCI_SKIP_MEMORY_FRESHNESS=1`.

**Stage 0 is complete and its gate is met under this amendment.** Both Start
Rule conditions hold:

- the local Plan 011 work-bound lane still proves anchored relationship work
  scales with anchored candidates (`zig build test-core -Doptimize=ReleaseFast`,
  98/98); and
- the external Java sample contains an addressable subset of **135** public
  static invocations, against a threshold of at least 100 invocations or 5% of
  receiver-qualified unresolved calls, whichever is smaller.

Do not re-open the gate on the old subject. If a later stage discovers that the
135 cannot be reached exactly, stop and amend this plan again rather than
widening the rule to reach the number.

## Scope

- Write an ADR for Java static `CALLS` facts before semantic code changes.
- Add a deterministic Java fixture matrix for static calls, name obscuring,
  unresolved reasons, provider/class-shape changes, and exact negative cases.
- Add a Java analyzer-side projection for current declared methods, their
  `static` modifier, their access within the covered subset, class shape, and the
  units that may read them.
- Prove, for a simple-name receiver, that no binding introducer in scope gives
  the name another meaning, so a class name is never read past a variable.
- Resolve static-qualified Java calls only when receiver type, method target,
  `static` modifier, access, source-root visibility, and class shape are exactly
  established.
- Re-measure the external sample after implementation and compare against the
  Stage 0 baseline.
- Update capability documentation, local preview coverage notes, `MEMORY.md`,
  and the progress log.

## Non-Scope

Do not resolve **instance** receivers: locals, parameters, fields,
`new Type(...)`, chained or field receivers, `super`, class literals, or string
literals. That subset is measured and deferred in
[Follow-up 014](../followups/014_java_instance_receiver_calls.md). A call whose
receiver is a value stays unresolved with its current reason.

Do not relax the supertype guard on the referring class, and do not traverse a
type hierarchy. That is
[Follow-up 013](../followups/013_java_supertype_guard_relaxation.md).

Do not read or execute Maven, Gradle, Bazel, `module-info.java`, jars, class
files, generated sources outside the indexed working copy, or any network
resource.

Do not close [Follow-up 011](../followups/011_java_cross_module_visibility.md)
or add cross-module visibility. The existing ADR 008 source-root boundary stays
in force.

Do not admit shared-core `module`, `IMPORTS`, package entities, classpath
entities, a new method-signature entity kind, inheritance entities, or dispatch
entities. If the work seems to require one, stop and create the CORE/ADR input
instead of smuggling it through a Java plan. Method signatures may remain part
of existing Java method definition identity.

Do not add approximate, name-match, text-search, vector, popularity, or
best-effort resolution. A call whose receiver type, obscuring status, target
method, access, or class shape is not exactly established stays unresolved.

Do not resolve static imports (`import static a.b.C.m;` used as a bare `m()`),
scoped receivers (`a.b.C.m()`), static field reads, constructor calls, field
reads or writes, wildcard imports, inheritance, virtual dispatch, interface
method resolution, or overload selection by argument type.

Do not change MCP tool JSON shape, tool arguments, cursor semantics,
response-budget semantics, `semantic_contract_version`, or the text fallback.
New Java facts surface through existing relationship, resolution, producer,
freshness, evidence, extension labels, and diagnostic fields.

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
- [SPEC.md](../../SPEC.md), for the language-extension catalogue and coverage
  ownership, including the invalidation-producer roster.
- [CORE.md](../../CORE.md), for the shared-core roster and admission rules.
- [ADR 003](../adr/003_reject_name_match_assertions.md), for rejecting
  repository-wide name matching as graph authority.
- [ADR 004](../adr/004_allow_java_same_package_type_resolution.md), for
  analyzer-side Java package projections and provider dependencies.
- [ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md),
  for the closest accepted cross-unit `CALLS` precedent.
- [ADR 008](../adr/008_java_visibility_boundaries.md), for derived source-root
  visibility.
- [Plan 012 progress](../reports/012_java_semantic_quality_without_query_regression_progress.md),
  for the Stage 0 baseline and every threshold count.
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md) and
  [Plan 011 progress](../reports/011_external_scale_graph_query_indexes_progress.md).
- [docs/spec/capability_matrix.md](../spec/capability_matrix.md), for supported
  language coverage wording.
- [docs/mcp/local_preview.md](../mcp/local_preview.md), for MCP preview coverage
  wording.
- [Product adoption strategy](../design/002_product_adoption_strategy.md), for
  the adoption value this plan is meant to serve.

## Current Evidence

The current Java frontend records top-level class and method definitions, field
and method-return type references, same-source-root/single-type-import type
references, and very narrow same-class unqualified invocation facts.

Qualified calls are intentionally unresolved. `emitInvocation` treats any
`method_invocation` with an `object` field as a designator carrying the full
invocation text, and `invocationTarget` returns the reason "the invocation is
qualified by a receiver this frontend does not resolve". Stage 0 classified all
4,624 of those in its sample:

| Receiver | Count | This plan |
| --- | ---: | --- |
| Class name (static call) | 1,041 | **subject** |
| Value: local, parameter, field, `new`, chained, `super`, literal | 3,583 | Follow-up 014 |

Of the 1,041 class-name receivers, the exact subset is 135: the receiver
resolves through `resolveType` to one current top-level class inside the ADR 008
boundary, the class declares no supertypes, exactly one method of the invoked
name is declared in it, and that method is `static` and public. The rest are
blocked by evidence that does not exist in the working copy — 382 name a class
no indexed unit declares, 247 are blocked by the supertype guard on the referring
class, 113 reach a class outside the ADR 008 boundary, 74 are overloaded.

`resolveType` already does the receiver half of this work. What it does **not**
do is prove that a simple name is a type rather than a variable: Java lets a
variable obscure a type of the same name, so a static-call rule that reads
`foo.m()` as a type whenever a class named `foo` exists would invent targets.
Stage 0 measured the strict rule — no parameter, local, field, or other binding
introducer may declare the name, and the enclosing class must declare no
supertypes so no inherited field can obscure it — and it costs nothing: all 135
already satisfy it.

The Java package table is the right precedent for projection discipline. It is
an analyzer-side projection, not a graph model; it keeps only hints, re-reads
graph facts before answering, and creates no package entity, module entity, or
import relationship. `Upkeep` reanalyzes providers, dependents, package
declarers, and single-type importers so cross-unit facts and
unresolved-to-resolved transitions stay maintainable.

Method lookup can re-read method entities from the graph, but two preconditions
are not graph facts today. A Java class entity carries `java.construct` and
`java.package`, not whether it declares supertypes; a Java method entity carries
`java.construct`, `java.return_type` and `java.package`, not its access and not
whether it is `static`. Stage 1 and Stage 3 must decide and document how that
evidence is carried.

Plan 011's indexed access model is confirmed externally by Stage 0 and must not
regress.

## Plan-Level Decisions

**D1 - ADR before semantic implementation.** Stage 1 creates
`docs/adr/009_java_static_calls.md`. No stage after Stage 0 may emit new Java
static `CALLS` facts until that ADR is accepted. If the ADR rejects or materially
changes the semantics proposed here, update this plan before continuing.

**D2 - The proposed `CALLS` meaning is the declared static method.** A static
method is selected at compile time and is not dispatched, so this plan's `CALLS`
names the one static method the target class declares under that name. Dynamic
dispatch, overriding, and hiding remain not recorded and must be stated in the
capability matrix.

**D3 - A simple-name receiver is a type only when nothing can obscure it.** The
frontend must prove that no parameter, local variable, field, or other
binding-introducing construct in scope declares that name, and that the
enclosing class declares no supertypes, so no inherited field can obscure it.
An uncovered binding introducer poisons the name exactly as it would a value
receiver. This is the cheap half of the receiver environment: it needs the set
of names bound at the invocation, never their types.

**D4 - Class shape and method modifiers are graph-carried Java extension
evidence.** The proposed Stage 1 answer is additive Java extension labels on
existing Java definitions, not passing provider source into another unit's
frontend and not reparsing provider source during lookup. At minimum, class
definitions need a label such as `java.supertypes = none|declared`, and method
definitions need covered access and a `static` marker. These labels are graph
assertions produced by the Java frontend, visible as extension data, and owned by
SPEC/capability documentation. If ADR 009 rejects labels or requires
provider-source re-reading instead, this plan must be amended before Stage 3
because the current frontend contract does not expose provider bytes or trees to
dependent analysis.

**D5 - Method targets require uniqueness, `static`, covered access,
source-root visibility, and safe class shape.** Overloads stay unresolved
because this plan does not type arguments. A non-static method named through a
class receiver stays unresolved, because it is not a call Java would compile.
Methods in target classes with declared supertypes stay unresolved, because a
hidden static method could change the target. Cross-unit private/protected/
package access must be either proven inside the covered access subset or left
unresolved. ADR 009 set that subset: `public`, plus any access when the target
class is the top-level class enclosing the invocation.

**D6 - Incremental maintenance covers class-shape changes, not only method-set
changes.** A unit whose call depends on a receiver class must be reachable when
that class adds, removes, renames or overloads a method, changes a method's
access or `static` modifier within the covered subset, or adds or removes
declared supertypes. Resolved cross-unit calls must also declare provider
dependencies.

**D7 - Speed regressions are measured as work first.** External wall-clock
numbers are recorded because users feel them, but acceptance relies on
deterministic work bounds and growth shape: receiver and member lookup must use
bounded candidate tables, not repository-wide scans in per-call paths.
Dependency propagation cost and exhaustion are part of the write-path budget.

**D8 - Instance receivers and the supertype guard are follow-up work.** Both are
measured; neither is implemented here. Follow-ups 013 and 014 own their
acceptance direction.

**D9 - Public surfaces stay shape-compatible.** Better Java resolution changes
graph content and capability docs, not MCP tool contracts. New outcomes appear
as existing `fact` or `unresolved` relationships with evidence and producer
metadata.

## Architecture Boundaries

1. **Java frontend**
Responsibility: reading a receiver name as a type, proving nothing obscures it,
class-shape evidence, Java method candidates, `static` and access checks in the
covered subset, and the rules that decide whether a Java relationship is a fact
or unresolved.
Does not know about: MCP payload shape, response budgets, storage backends, or
other frontends' semantics.

2. **Java analyzer projections**
Responsibility: candidate tables for packages, imports, methods, class shape,
and readers. Hints may be conservative supersets.
Does not know about: graph authority. A projection may find or re-read graph
facts and Java extension labels, but a fact exists only when the frontend
records it in the graph with exact evidence.

3. **Shared core**
Responsibility: entities, relationships, assertions, resolution categories,
freshness, identity, dependencies, and snapshots.
Does not know about: Java scoping, Java packages, Java source roots, method
overloads, access modifiers, `static`, class shape, or inheritance.

4. **Incremental upkeep**
Responsibility: reanalyzing units affected by provider, class-shape, and
projection changes.
Does not know about: choosing Java facts. It preserves freshness and dependency
propagation. It may over-invalidate through hints, but must not under-invalidate
facts.

5. **MCP preview**
Responsibility: projecting the graph as it exists.
Does not know about: this plan. Tool contracts do not change.

## Stages

### Stage 0: Post-Plan-011 External Baseline And Addressability Gate

**Completed 2026-09-19. Verdict on the original subject: no-go. Verdict under
Amendment 1: go, at 135 against a threshold of 100.**

Its required behavior, results, method, and limits are in
[the progress log](../reports/012_java_semantic_quality_without_query_regression_progress.md).
Do not re-run it before Stage 7; Stage 7 re-runs the same probe for comparison.

### Stage 1: ADR For Java Static Calls

Purpose: record the durable Java semantic decision before implementation.

Depends on: Stage 0.

Likely files:

- `docs/adr/009_java_static_calls.md`
- [docs/adr/README.md](../adr/README.md), whose `## Records` list ends at 008
- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
- [GLOSSARY.md](../../GLOSSARY.md), for any durable term the ADR settles
- this plan, if the ADR changes the stage contract

Required behavior:

- Write an ADR with all eight answers from constitution section 11, and add it
  to the `## Records` list in `docs/adr/README.md` in the same commit.
- Record, for every decision below, at least one rejected alternative and why it
  was rejected. This plan states a proposed answer for most of them; a proposal
  is input, not the decision. An ADR that only restates this plan leaves no
  record of what was weighed.
- Decide that Java `CALLS` through a class-name receiver means the declared
  static method of that class, and explicitly leave hiding, dispatch, and
  overload selection unrecorded.
- Decide the obscuring rule: what must be proved before a simple name is read as
  a type, which binding introducers poison it, and what happens when the
  enclosing class declares supertypes.
- Decide how class-shape and method-modifier evidence is established. This
  plan's proposed answer is additive Java extension labels on existing Java
  definitions, not provider-source re-reading by the Java projection.
- Decide the covered method-access subset, and state what happens to private,
  protected, package-private, and public methods outside that subset.
- Decide whether a non-static method reached through a class receiver gets its
  own unresolved reason, or shares one with "no such method".
- State that build descriptors, cross-module visibility, inheritance entities,
  dispatch, overload resolution by argument type, static imports, scoped
  receivers, `module`, and `IMPORTS` are not admitted.
- Name the fixture families Stage 2 and Stage 5 must satisfy.
- Own the Java semantic vocabulary it introduces, and record that ownership.
  Obscuring proof, binding introducer, covered access subset, and static target
  are ADR-owned normative terms, not glossary entries: `GLOSSARY.md` is not
  normative and must not restate them. Add or revise a glossary entry only for a
  term whose meaning is project-wide rather than Java-specific, such as class
  shape.

Done when:

- The ADR is committed with `status: accepted`, all eight constitution section
  11 answers are complete, and the executing agent has recorded drift-control
  checks against the plan's source-of-truth list. If human review rejects or
  changes the ADR, this plan stops until the ADR and plan agree.
- Any ADR decision that differs from this plan is reflected in this plan before
  later stages execute.

### Stage 2: Java Quality Fixtures And Counters

Purpose: make the exactness target executable before changing behavior.

Depends on: Stage 1.

Likely files:

- `tests/vertical_slice_test.zig` for in-memory Java semantic fixtures, matching
  the existing ADR 008/import precedent.
- File fixtures only when a runtime/dogfood/profile behavior specifically needs
  filesystem layout; if used, the stage must state how global scans and
  `preview-gate` observe them.
- Java frontend tests in the existing full Zig test lane.
- `src/core/dependencies.zig`, only if the propagation-rounds counter below
  needs exposing; that counter is the one piece of this stage whose narrow lane
  is `zig build test-core`.
- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`

Required behavior:

- Add committed fixture cases for static calls:
  - `Helper.m()` to a unique public static method of a class with no supertypes,
    with the class supplied by the same unit, the same source root, a
    standard-layout test-to-main root, and a single-type import;
  - the same call where the method is not static, is overloaded, is
    package-private, protected or private in another unit, or does not exist;
  - `Self.m()` inside the class `Self` itself, where the static method is
    private, which ADR 009 admits as the one non-public case;
  - the target class declares a superclass, and separately an interface;
  - the receiver class is outside the ADR 008 boundary;
  - the receiver name is ambiguous, is a type parameter, names a member type, or
    names a non-class type declared in the unit;
  - the invocation is inside a nested class body.
- Add obscuring fixtures, one per binding-introducing Java node that must poison
  a receiver name unless the ADR covers it:
  - `formal_parameter` and `spread_parameter`;
  - `local_variable_declaration`, including a declaration after the call;
  - `field_declaration`, including a field whose name equals a class name;
  - `enhanced_for_statement`;
  - `catch_formal_parameter`;
  - `resource`;
  - `lambda_expression` / `inferred_parameters`;
  - `type_pattern` and `record_pattern`;
  - an enclosing class with supertypes, where an inherited field could obscure
    the name.
- Add provider/class-shape edit cases:
  - target method added after an unresolved call;
  - target method removed after a fact;
  - target method overloaded after a fact;
  - target method loses `static` after a fact;
  - target method access changed so a fact becomes unresolved;
  - receiver class moved across the ADR 008 boundary;
  - provider adds a declared supertype after a fact, making the call unresolved;
  - provider removes a declared supertype after an unresolved call, making it
    eligible for resolution if every other condition holds.
- Add or expose the test-only counters that need no mechanism this stage has not
  built yet: call-resolution work, dependency declaration count, provider
  reanalysis work, and propagation exhaustion. `Dependencies.propagate` already
  reports `exhausted`; the round count is a local variable, so exposing it is a
  small shared-core change rather than a fixture change, and it belongs here
  only because Stage 3 and Stage 5 both measure against it.
- Leave class-shape reader-work counters to Stage 3, which builds the readers
  they count. A counter lands with its mechanism; this stage does not stub
  counters for work that does not exist.
- Every counter is test-only and must not change MCP output, budgets, or any
  published claim.
- Stage 2 fixtures pin cases, not old reason strings. Stage 4 and Stage 5 are
  expected to replace some unresolved explanations with more precise ones.

Done when:

- The fixture matrix exists with pre-implementation expectations for every case
  before behavior changes.
- Negative cases assert the applicable category and reason family, not just
  "no fact".
- The progress log contains the stage's risk matrix update and focused command
  results.

### Stage 3: Java Method Projection, Class Shape, And Invalidation

Purpose: add the candidate infrastructure needed for static calls, without yet
emitting new call facts.

Depends on: Stage 2.

Likely files:

- `src/frontends/java.zig`
- `src/frontends/java_packages.zig` or a new `src/frontends/java_members.zig`
- `src/frontends/root.zig`
- `src/root.zig`
- [SPEC.md](../../SPEC.md)
- focused tests/fixtures

Required behavior:

- Build a Java method/class projection from current graph facts and Java
  extension labels. At minimum, each current top-level Java class candidate
  carries: package, simple class name, class entity id, provider unit, source
  root, declared-supertypes shape, and current declared methods grouped by
  simple method name, each with its covered access and `static` marker.
- Re-read graph facts for entities/methods and Java extension labels for class
  shape before answering. Hints may grow and over-invalidate, but they must not
  be authority.
- Preserve snapshot/query indexes from Plan 011. No relationship query path may
  scan every assertion to answer one call.
- Add reader-hint storage and the `Upkeep` path that Stage 5 will populate for
  units that mention an exact receiver class and method name. The path must
  cover calls that are currently unresolved because the method is missing,
  overloaded, non-static, access-blocked, or blocked by class shape.
- Extend `Upkeep` so a class-shape change reanalyzes affected readers even when
  the previous relationship had no provider dependency because it was
  unresolved. Class shape for this plan includes method set, covered method
  access, method `static` modifiers, and declared supertypes.
- Do not reuse Java package-export invalidation for method or class-shape
  changes. The existing `java_packages.Export`/`Export.eql`/`Upkeep.markMissing`
  path detects only package plus top-level class-name export presence. Adding a
  shape fingerprint there would mark the whole package changed for a one-method
  edit and would reanalyze package declarers/importers unrelated to that method.
  Use a separate aspect-grained class-shape channel keyed at least by receiver
  class and invoked method name, backed by reader hints.
- Capture class-shape before/after in `Upkeep` alongside the package export
  before/after path, and mark only readers of the changed class/method/aspect.
  If the implementation cannot keep this bounded without package-wide
  invalidation, stop and amend this plan before Stage 5.
- Preserve the existing one-round-settles invariant for projection changes:
  method sets and class shape depend only on a unit's own contents. If an
  implementation violates that invariant, stop and redesign the invalidation
  stage.
- For resolved cross-unit method targets, declare provider dependencies so
  provider edits invalidate callers.
- Measure dependency declaration count, propagation rounds, and whether
  `dependencies.propagate` exhausts its budget on the stage fixtures.

Done when:

- Projection tests prove method-set lookup, uniqueness/overload classification,
  `static` and covered access classification, source-root visibility,
  stale-provider rejection, class-shape change detection, and reader
  invalidation through seeded reader hints.
- Edit-history tests prove that changing one method or class-shape label
  reanalyzes only relevant hinted readers, not every declarer/importer in the
  package.
- Existing Java package/import tests still pass unchanged.
- `zig build test-mcp` passes. The new class-shape labels are MCP-visible:
  `extension.labels` is serialized into tool responses, so this stage changes
  payload content even though it changes no tool contract and emits no new call
  fact.
- No new Java call fact is emitted by this stage.

### Stage 4: Reading A Receiver Name As A Type

Purpose: let the Java frontend decide, exactly, whether a simple-name receiver is
a class name or a value, without inferring any value's type.

Depends on: Stage 3.

Likely files:

- `src/frontends/java.zig`
- focused tests/fixtures

Required behavior:

- Collect the set of names bound at an invocation, by lexical scope: formal and
  spread parameters, local variable declarators visible at that point, class
  field names, and every other binding-introducing construct in the ADR's list.
  Only names are needed, never their types.
- Treat a receiver name as a class name only when no such binding claims it and
  the enclosing class declares no supertypes, so no inherited field can obscure
  it. Anything else leaves the call unresolved.
- Resolve the name through the existing `resolveType`, unchanged, so type
  parameters, member types, static imports, non-class types, single-type
  imports, the same-package rule, and the ADR 008 boundary all keep their current
  meanings and their current explanations.
- Keep nested class bodies as a boundary. A call inside a class body declared
  within a method is still analyzed as nested and is not resolved.
- Record distinct unresolved reasons for: the name is bound by a binding
  introducer; the enclosing class has supertypes so an inherited field could
  obscure the name; the name does not resolve to a current top-level class; the
  class is outside the visibility boundary; and the receiver expression is not a
  simple name.
- Emit no call fact in this stage; the decision must be testable on its own.

Done when:

- Fixture cases prove obscuring by every binding introducer in the ADR's list,
  before-declaration use, field names that equal class names, inherited-field
  poisoning, nested class bodies, and source-root visibility.
- Existing `resolveType` explanations are unchanged for every case that reached
  them before.

### Stage 5: Static Call Facts

Purpose: convert the measured static-call gap into exact Java `CALLS` facts.

Depends on: Stage 4.

Likely files:

- `src/frontends/java.zig`
- Java member projection files from Stage 3
- focused tests/fixtures

Required behavior:

- Resolve a class-qualified invocation to a fact only when all of these hold:
  - Stage 4 established the receiver name as exactly one current Java top-level
    class, with nothing obscuring it;
  - the class is inside the ADR 008 visibility boundary;
  - the method projection finds exactly one current declared method of that name
    in the target class;
  - that method is `static`;
  - its access is inside the subset accepted by ADR 009;
  - the target class declares no supertypes;
  - the invocation is not inside a nested class body.
- Keep the full invocation text as the designator for unresolved qualified
  calls, as today.
- Declare provider dependencies for the receiver class's provider unit.
- Populate method/class-shape reader hints for exact receiver class and
  method-name pairs, including unresolved calls that could become facts after a
  provider method or class-shape change.
- Record distinct unresolved reasons for missing method, overloaded method,
  non-static method, inaccessible method outside the covered subset, and target
  class has supertypes.
- Re-run Stage 2 fixtures with expected facts enabled for covered positive cases
  and expected unresolved reason families for every negative case.

Done when:

- Covered static calls become `CALLS` facts in committed fixtures.
- Every negative case remains unresolved with an exact reason family.
- Provider method add/remove/overload/access/`static` edits reanalyze the caller
  and change only the affected claim.
- Provider class-shape edits, especially adding a declared supertype after a
  fact, reanalyze the caller and remove stale facts from default current
  queries.
- Focused counters show lookup work bounded by candidate tables, not by all Java
  units or all graph assertions per invocation.
- Dependency declaration count, propagation rounds, and propagation exhaustion
  are recorded.

### Stage 6: Follow-Up Discipline

Purpose: keep the deferred Java work honest after the facts land.

Depends on: Stage 5.

Likely files:

- `docs/followups/013_java_supertype_guard_relaxation.md`
- `docs/followups/014_java_instance_receiver_calls.md`
- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`

Required behavior:

- Re-run the Stage 0 classification after Stage 5 and record what moved. Static
  calls that land as facts must leave both follow-ups' measured subsets
  unchanged or smaller, never larger by side effect.
- Update Follow-up 013 and Follow-up 014 with the post-implementation counts, or
  record that the Stage 0 counts still stand.
- Do not implement either follow-up in this plan.

Done when:

- Both follow-ups carry current counts and an acceptance direction that a future
  plan can execute without re-deriving this plan's measurements.

### Stage 7: External Remeasurement, Documentation, And Closure

Purpose: prove the plan improved exact Java answers without query regression,
and leave the project documents aligned.

Depends on: Stage 5 and Stage 6.

Likely files:

- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
- [docs/spec/capability_matrix.md](../spec/capability_matrix.md)
- [SPEC.md](../../SPEC.md)
- [docs/mcp/local_preview.md](../mcp/local_preview.md)
- [MEMORY.md](../../MEMORY.md)
- [GLOSSARY.md](../../GLOSSARY.md)
- this plan document
- optional follow-ups

Required behavior:

- Re-run the Stage 0 external probe, at the same commit and in both build modes,
  and compare:
  - exact call facts and unresolved reasons;
  - exact reference facts and unresolved reasons;
  - `semidx_health`, `semidx_references`, and `semidx_context depth=2` work
    shape and wall-clock observations;
  - cold index, no-op refresh, one-file refresh, provider-method-change refresh,
    and provider-class-shape-change refresh work;
  - dependency declaration count, propagation rounds, and propagation
    exhaustion;
  - memory impact of new projection tables and new Java extension labels, against
    the Stage 0 baselines of 351 MB (Debug) and 186 MB (ReleaseFast) maximum
    resident set size;
  - response-size impact of the new labels: bytes per Java definition item at
    `detail=full`, and whether any habit-loop call now exhausts its budget or
    needs more pages than the Stage 0 baseline at the same
    `max_response_bytes`. Budget semantics are unchanged; what the same budget
    now fits is an observation this plan owes its consumers.
- Compare results against the Stage 0 addressable subset of **135** public static
  invocations. If ADR 009 accepts more than public methods, Stage 7 must
  recalculate that denominator and record both the public lower-bound and
  accepted-access counts. The plan is not complete unless at least 100 and at
  least 80% of the accepted-access measured subset become exact `CALLS` facts in
  the same sample. If the 80% bar is missed, closure is allowed only when every
  miss has a recorded out-of-subset reason; otherwise reopen the plan.
- Update the capability matrix and preview reference with the exact covered Java
  static-call cases and the cases left unresolved, including static target versus
  dispatch, the access subset, the obscuring rule, class-shape labels, and the
  instance receivers that stay unresolved.
- Update `SPEC.md` where this plan moved requirements it owns: name the new Java
  member/class-shape invalidation producer and Java extension labels, or
  explicitly record why those owner rows do not change.
- Update the Java capability matrix definition-label and "Not recorded" rows so
  `java.supertypes`, method access and `static` labels, and the remaining
  inheritance and dispatch exclusions do not contradict each other.
- Check every durable term this plan or ADR 009 introduced against
  `GLOSSARY.md`, and either add the entry or record which document owns the
  term. Terms that stay owned elsewhere are listed in the progress log with
  their owner, not copied into the glossary.
- Update `MEMORY.md` by compression, not by appending a progress log.
- If a stage commit changes behavior that belongs in `MEMORY.md`, update it in
  that commit or record in the progress log why the current memory entry remains
  accurate. A push may use `SCI_SKIP_MEMORY_FRESHNESS=1` only after that check
  and only when no memory update is actually due.
- Mark the plan and progress log complete only after verification evidence and
  residual risk are recorded.

Done when:

- The external remeasurement shows at least 100 and at least 80% of the
  accepted-access measured subset as new exact Java static call facts in the
  covered cases. If the 80% bar is missed, every miss has a recorded
  out-of-subset reason; otherwise the plan is reopened before closure.
- No new approximate assertions are introduced.
- Plan 011's anchored query work bound still holds, and the Stage 0 external
  latency observations have not regressed.
- Dependency propagation does not silently leave current stale facts behind; any
  exhaustion is reported and treated as residual risk.
- Documentation states the exact capability boundary without broad Java claims.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Durable Java `CALLS` semantics are authorized | Plan implements a new semantic relationship without an ADR | ADR plus plan gate | ADR 009 answers all eight constitutional questions | ADR rejects or changes the proposed rule, requiring plan amendment | Stage 1 ADR and progress log |
| A receiver name is a type only when nothing obscures it | A variable named like a class turns into a static call fact | Fixture/golden | Bound-name set is proved empty for that name, and the enclosing class has no supertypes | Local, parameter, field, for-each, catch, resource, lambda, pattern with the same name; inherited field under a supertype | Stage 2 and Stage 4 fixtures |
| Static call facts are exact | False `CALLS` facts from a non-static, overloaded, or inaccessible method | Java fixture/golden plus frontend integration | Exactly one declared method of that name, `static`, inside the access subset | Non-static method, overloads, package-private target, class with supertypes, nested class body | Stage 5 fixture tests and progress-log counts |
| Unresolved remains distinguishable | Unsupported, unavailable, ambiguous, obscured, and inaccessible cases look alike | Fixture/golden | Each decline reason family appears in graph output | No-source, out-of-scope, obscured name, non-static, inaccessible, overloaded | Stage 2, Stage 4 and Stage 5 negative fixtures |
| Instance receivers stay unresolved | The static rule leaks into value receivers | Fixture/golden | A value receiver keeps its current reason and designator | `local.m()`, `field.m()`, `new T().m()`, `a.b().c()`, `super.m()` | Stage 5 negative fixtures |
| Incremental freshness holds | Caller stays stale after provider method/class-shape change | Focused integration/edit-history test | Provider method, `static`, access, or class-shape change reanalyzes affected readers | Fact becomes unresolved after provider adds `extends` or drops `static`; unresolved becomes fact after a static method appears | Stage 3/5 edit tests |
| Query speed is preserved | Per-call lookup scans all units/assertions | Test-only work counters plus external observation | Candidate work grows with class/method candidates, not repository size | Old full-scan path fails the bound | Stage 0/5/7 work measurements |
| Write path stays bounded | Method/class-shape reader hints cause repository-wide reanalysis | Synthetic doubled-corpus integration test | Provider change reanalyzes readers, not all units | Unit stops reading a method but remains hinted as harmless superset; editing one method does not reanalyze unrelated package declarers/importers | Stage 3/7 refresh measurements |
| Dependency propagation stays useful | New cross-unit call dependencies exceed propagation budget or make propagation too costly | Integration and scale/work test | Declaration count, rounds, and exhaustion recorded | Chain over 64 rounds emits `analysis_unavailable` and residual risk | Stage 0/5/7 measurements |
| Source-root boundary remains intact | Receiver class lookup crosses modules by name | Fixture/golden | Same root and test-to-main resolve; other roots unresolved | Cross-module same package with no admitted dependency | ADR 008 fixtures reused in Stage 3/5 |
| Method access is not guessed | Private/protected/package-private method becomes cross-unit fact without proof | Fixture/golden | Covered access subset is enforced | Private static method in another class, protected static method outside covered subset | Stage 1 ADR and Stage 5 fixtures |
| Public contracts unchanged | MCP clients see shape drift | MCP tests/runtime smoke | Existing tool schemas and payload families still pass | New Java facts through existing relationship fields only | `zig build test-mcp`, `zig build preview-gate` |
| Capability docs stay honest | Docs imply broad Java call or dispatch support | Documentation review | Matrix names exact static cases and exclusions | Instance receivers, cross-module, overloads, hiding, classpath, dynamic dispatch left unresolved | Stage 7 doc diff |

## Verification

Use the narrowest meaningful command first, then widen:

- `./scripts/check-zig-version.sh`
- `zig fmt --check build.zig src tests`
- focused Java frontend tests named in the progress log, if the repository has
  a focused command for them
- `zig build test` for Java frontend, projection, tree-sitter, fixture, and
  edit-history changes; this is the narrowest meaningful lane for most of this
  plan because `test-core` does not include `src/frontends/`
- `zig build test-core` only for shared-core changes that do not depend on
  parsers or frontends
- `zig build test-mcp` when MCP-visible graph output is changed
- `zig build dogfood` and `zig build preview-gate` before closure
- `zig build test-core -Doptimize=ReleaseFast` only for shared-core scale lanes;
  Java projection scale checks must run in the full parser-dependent lane or in
  a stage-specific command named in the progress log

External repository measurements are evidence, not committed conformance. Pin
the repository and commit in the progress log, do not commit its source, and do
not make network access part of a required local lane.

## Drift Control

Before implementation, check this plan against `RULES.md`, the architecture
constitution, ADR 003, ADR 004, ADR 006, ADR 008, Follow-ups 011, 013 and 014,
Plan 010 progress, Plan 011 progress, this plan's progress log, `SPEC.md`,
`CORE.md`, `MEMORY.md`, `GLOSSARY.md`, the capability matrix, the adoption
strategy, and the current Java frontend.

During closure:

- If ADR 009 accepts semantics that differ from this plan, update this plan
  before code changes.
- If a new durable decision changes Java semantics beyond ADR 009, write or
  revise an ADR instead of burying it in the progress log.
- If a shared-core kind starts to look necessary, stop and route it through
  `CORE.md` and a future plan.
- Give every durable term one owner. Java-specific normative vocabulary belongs
  to ADR 009; measurement vocabulary that exists only for this plan, such as
  addressable subset and go-threshold count, belongs to this plan and its
  progress log; project-wide concepts belong to `GLOSSARY.md`. A term used in
  two of those senses is drift, not shorthand.
- Keep README out of this unless public positioning or quick-start behavior
  changes. Stage evidence belongs in the progress log.
- Keep `MEMORY.md` below its policy limit by replacing stale near-term text with
  links to the plan and progress log.

## Definition Of Done

This plan is complete when:

- the post-Plan-011 external Java baseline and addressable subsets are recorded
  (done in Stage 0);
- ADR 009 is accepted and every later stage follows it;
- static calls in the covered subset become exact facts at or above 100 in the
  Stage 0 sample, and either at least 80% of the accepted-access measured subset
  becomes exact or every miss below the 80% bar has a recorded out-of-subset
  reason;
- a simple-name receiver is never read as a type where a binding or an inherited
  field could obscure it;
- unsupported, ambiguous, stale, out-of-scope, inaccessible, non-static,
  overloaded, obscured, and open-hierarchy cases remain unresolved with distinct
  reason families;
- instance receivers remain unresolved and are tracked by Follow-up 014;
- provider method and class-shape changes maintain freshness incrementally;
- query, write-path, and dependency-propagation work bounds show no regression
  from Plan 011's indexed access model, and the Stage 0 external latency
  observations do not regress;
- the supertype guard stays unchanged and is owned by Follow-up 013;
- capability docs and `MEMORY.md` describe the new Java boundary honestly; and
- every stage's verification, skipped checks, and residual risk are recorded in
  the progress log.
