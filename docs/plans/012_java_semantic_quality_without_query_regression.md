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

Increase exact Java impact answers on an external-scale Java repository without
losing the graph-query speed Plan 011 just bought.

Plan 010 showed that Java's next value gap is semantic coverage, not the
source-root boundary. In its external sample, 4,624 of 5,662 unresolved calls
were qualified by a receiver the frontend did not resolve. The supertype guard
was also material: before Plan 010's single-type import stage, it declined 64
of 103 unresolved references whose target had source in the working copy. After
single-type imports landed, that denominator fell to 98 and the supertype
bucket was not remeasured. Stage 0 of this plan therefore remeasures both
receiver and supertype opportunities instead of inheriting the old percentage.

Plan 011 removed the known query-work bottleneck but did not re-run the external
apache/dubbo wall-clock probe. This plan joins those facts: first prove the
habit loop is still fast enough after Plan 011 and that the receiver subset is
large enough to justify work, then widen Java only where the frontend can
establish exact source-derived facts.

## Product Principle

When a choice is available, decide in this order:

1. **Exactness beats recall.** A new Java edge is useful only if it remains a
   fact under the constitution's distinction between fact, unresolved, and
   approximate assertion.
2. **The habit loop must stay usable.** A richer graph that makes
   `semidx_health` -> `semidx_outline` -> `semidx_repo_map` ->
   `semidx_find_definitions` -> `semidx_references` / `semidx_context` slow
   enough to abandon is a product regression.
3. **Durable semantics need an ADR.** Cross-unit receiver-qualified Java
   `CALLS` facts are new language semantics. This plan may propose them, but
   implementation waits for an accepted ADR that answers the constitutional
   decision test.
4. **Java projections are not graph authority.** Package, source-root, method,
   receiver, and class-shape lookup tables may find candidates. The graph
   records only the resulting assertion, its resolution, producer, evidence,
   freshness, and dependencies.
5. **Unresolved reasons are product output.** A negative answer must say whether
   the frontend lacked a receiver type, saw overloads, hit supertypes, crossed a
   source-root boundary, hit an uncovered Java declaration kind, or found no
   source.
6. **No Java build system enters by accident.** Build descriptors, classpaths,
   modules, jars, and dependency graphs stay out unless a future plan and ADR
   admit them explicitly.

## Start Rule

Read before starting implementation:

- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  especially the external Java probe, unresolved-reason measurements, and
  residual risk.
- [Plan 011 progress](../reports/011_external_scale_graph_query_indexes_progress.md),
  especially the statement that external Java latency was not re-measured.
- [Follow-up 012](../followups/012_external_scale_query_latency.md), because
  Stage 0 is the external observation Plan 011 deliberately did not claim.
- [ADR 003](../adr/003_reject_name_match_assertions.md),
  [ADR 004](../adr/004_allow_java_same_package_type_resolution.md),
  [ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md),
  and [ADR 008](../adr/008_java_visibility_boundaries.md).
- [Follow-up 011](../followups/011_java_cross_module_visibility.md).
- [SPEC.md](../../SPEC.md), [CORE.md](../../CORE.md), and
  [docs/spec/capability_matrix.md](../spec/capability_matrix.md).
- [Product adoption strategy](../design/002_product_adoption_strategy.md).
- `src/frontends/java.zig`, `src/frontends/java_packages.zig`,
  `src/frontends/root.zig`, `src/root.zig`'s `Upkeep`, and
  `src/core/dependencies.zig`.
- [Testing policy](../agent-policy/testing.md).

Run `./scripts/check-zig-version.sh` before code work. Create
`docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
with progress-log frontmatter before the first code change.

Before pushing any stage commit, either update `MEMORY.md` when current
implementation reality, priorities, or known gaps changed, or record in the
progress log why the memory entry is still accurate before using
`SCI_SKIP_MEMORY_FRESHNESS=1`.

Stage 0 is a real go/no-go. Re-run the post-Plan-011 external Java speed and
quality baseline before changing Java semantics. Prefer the same apache/dubbo
commit used by Plan 010. If that root is unavailable, stop before code changes
and either make the external root available or amend this plan explicitly to
name a substitute repository. Do not infer a post-Plan-011 product latency from
Plan 011's synthetic work bound.

Proceed past Stage 0 only if both are true:

- the local Plan 011 work-bound lane still proves anchored relationship work
  scales with anchored candidates rather than total assertions; and
- the external Java sample contains a public-method lower-bound addressable
  receiver subset of at least 100 invocations, or at least 5% of
  receiver-qualified unresolved calls, whichever is smaller.

If the external MCP run cannot expose deterministic counters, record that
limitation and run the local work-bound lane before proceeding. Wall-clock
timing is recorded because users feel it; a slow clock alone reopens the plan
only when the work shape is also wrong or the habit loop is not usable.

## Scope

- Re-measure the Plan 010 external Java habit-loop probe after Plan 011's query
  indexes.
- Measure the addressable receiver-qualified call subset before implementation.
- Write an ADR for Java receiver-qualified `CALLS` facts before semantic code
  changes.
- Add a deterministic Java semantic-quality fixture matrix for receiver calls,
  unresolved reasons, provider/class-shape changes, and exact negative cases.
- Add Java analyzer-side projection(s) for current declared methods, method
  access within the covered subset, class shape, and the units that may read
  them.
- Add a conservative receiver type environment for Java method bodies.
- Resolve receiver-qualified Java calls only when receiver type, method target,
  access, source-root visibility, and class shape are exactly established.
- Measure the supertype-guard opportunity and write a follow-up if it is worth
  its own plan. This plan does not implement supertype relaxation.
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
entities, a new method-signature entity kind, inheritance entities, or dispatch
entities. If the work seems to require one, stop and create the CORE/ADR input
instead of smuggling it through a Java plan. Method signatures may remain part
of existing Java method definition identity.

Do not add approximate, name-match, text-search, vector, popularity, or
best-effort receiver resolution. A receiver-qualified call whose receiver type,
access, target method, or class shape is not exactly established stays
unresolved.

Do not record parameter-type or local-variable-type `REFERENCES` in this plan.
Receiver type evidence may be used internally by the Java frontend only if the
ADR accepts that as source-derived evidence for `CALLS` facts. If the ADR
requires those types to become graph assertions, this plan must be amended
before implementation because the graph population, measurements, and
capability matrix change materially.

Do not implement Java inheritance, virtual dispatch, interface method
resolution, overload selection by argument type, constructor calls, field reads
or writes, static method resolution through `ClassName.m()`, wildcard imports,
or build-tool classpaths.

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
- [Follow-up 011](../followups/011_java_cross_module_visibility.md), for the
  explicit cross-module boundary left open.
- [Follow-up 012](../followups/012_external_scale_query_latency.md), for the
  external latency observation Plan 011 intentionally did not claim.
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  for external Java quality evidence.
- [Plan 011 progress](../reports/011_external_scale_graph_query_indexes_progress.md),
  for query-index evidence and the unmeasured external-latency gap.
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

Qualified calls are intentionally unresolved today. `emitInvocation` treats any
`method_invocation` with an `object` field as a designator carrying the full
invocation text, and `invocationTarget` returns the reason "the invocation is
qualified by a receiver this frontend does not resolve". On the Plan 010 sample,
that reason accounted for 4,624 of 5,662 unresolved calls.

The supertype guard is also deliberate. `resolveType` declines cross-unit simple
type resolution when the enclosing class declares a superclass or interfaces,
because an inherited member type could shadow the apparent target. The often
quoted "62%" is a pre-import Plan 010 Stage 1 measurement: 64 of 103
in-working-copy unresolved references. After single-type imports, that
denominator became 98 and the exact current share was not remeasured. This plan
must not preserve the old percentage as a current claim.

The Java package table is the right precedent for projection discipline. It is
an analyzer-side projection, not a graph model; it keeps only hints, re-reads
graph facts before answering, and creates no package entity, module entity, or
import relationship. `Upkeep` reanalyzes providers, dependents, package
declarers, and single-type importers so cross-unit facts and
unresolved-to-resolved transitions stay maintainable.

Method lookup can re-read method entities from the graph, but some receiver-call
preconditions are not graph facts today. A Java class entity currently carries
`java.construct` and `java.package`, not whether it declares supertypes; a Java
method entity currently does not carry access, and parameter/local-variable
types are not recorded as relationships. The ADR and implementation stages must
decide and document which intermediate evidence is source-derived frontend
evidence and which, if any, becomes graph content.

Plan 011 proved anchored query work with synthetic local bounds past the size of
apache/dubbo, but it deliberately did not claim a new Dubbo wall-clock latency.
This plan cannot treat speed as already measured on the target adoption shape.

## Plan-Level Decisions

**D1 - ADR before semantic implementation.** Stage 1 creates
`docs/adr/009_java_receiver_qualified_calls.md`. No stage after Stage 0 may emit
new Java receiver-qualified `CALLS` facts until that ADR is accepted. If the ADR
rejects or materially changes the semantics proposed here, update this plan
before continuing.

**D2 - The proposed `CALLS` meaning is static target, not dispatch.** The ADR
must decide explicitly whether Java `CALLS` names the statically selected
declared method. The proposed rule is that an overriding subtype does not make a
static call target approximate; dynamic dispatch remains not recorded and must
be stated in the capability matrix.

**D3 - Parameter and local types stay internal evidence unless the ADR says
otherwise.** This plan's default is to use covered parameter/local/new-expression
types as source-derived evidence for receiver call resolution without emitting
new `REFERENCES` for those types. If that is unacceptable, the ADR must force a
plan amendment before implementation.

**D4 - Class shape is graph-carried Java extension evidence.** The proposed
Stage 1 answer is to add Java extension labels to existing Java definitions, not
to pass provider source into another unit's frontend and not to reparse provider
source during lookup. At minimum, class definitions need a label such as
`java.supertypes = none|declared`, and method definitions need a covered access
label. These labels are graph assertions produced by the Java frontend, visible
as extension data, and owned by SPEC/capability documentation. If ADR 009
rejects labels or requires provider-source re-reading instead, this plan must be
amended before Stage 3 because the current frontend contract does not expose
provider bytes or trees to dependent analysis.

**D5 - Receiver facts require a closed lexical receiver environment.** A simple
identifier receiver may be resolved only when every name-introducing construct
that could shadow it is either covered exactly or poisons the binding so the
call stays unresolved. Field fallback must not cross an unknown local binding.

**D6 - Method targets require uniqueness, covered access, source-root
visibility, and safe class shape.** Overloads stay unresolved because this plan
does not type arguments. Methods in target classes with declared supertypes stay
unresolved. Cross-unit private/protected/package access must be either proven
inside the covered access subset or left unresolved.

**D7 - Incremental maintenance covers class-shape changes, not only method-set
changes.** A unit whose call depends on a receiver class must be reachable when
that class adds/removes/renames/overloads a method, changes method access within
the covered subset, or adds/removes declared supertypes. Resolved cross-unit
calls must also declare provider dependencies.

**D8 - Speed regressions are measured as work first.** External wall-clock
numbers are recorded because users feel them, but acceptance relies on
deterministic work bounds and growth shape: receiver/member lookup must use
bounded candidate tables, not repository-wide scans in per-call paths.
Dependency propagation cost and exhaustion are part of the write-path budget.

**D9 - Supertype relaxation is follow-up work.** This plan measures the
supertype guard after receiver work. It may create a follow-up with acceptance
direction, but it does not implement hierarchy traversal or relax the guard.

**D10 - Public surfaces stay shape-compatible.** Better Java resolution changes
graph content and capability docs, not MCP tool contracts. New outcomes appear
as existing `fact` or `unresolved` relationships with evidence and producer
metadata.

## Architecture Boundaries

1. **Java frontend**
Responsibility: Java receiver/type evidence, local lexical scopes, class-shape
evidence, Java method candidates, access checks in the covered subset, and the
rules that decide whether a Java relationship is a fact or unresolved.
Does not know about: MCP payload shape, response budgets, storage backends, or
other frontends' semantics.

2. **Java analyzer projections**
Responsibility: candidate tables for packages, imports, methods, class shape,
receiver readers, and method readers. Hints may be conservative supersets.
Does not know about: graph authority. A projection may find or re-read graph
facts and Java extension labels, but a fact exists only when the frontend
records it in the graph with exact evidence.

3. **Shared core**
Responsibility: entities, relationships, assertions, resolution categories,
freshness, identity, dependencies, and snapshots.
Does not know about: Java receiver scoping, Java packages, Java source roots,
method overloads, access modifiers, class shape, or inheritance.

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

Purpose: establish the speed baseline, Java-quality baseline, and addressable
receiver subset this plan must preserve and improve.

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
  counts, current dependency declaration count, propagation exhaustion count if
  observable, and any deterministic work counters available from local scale
  lanes.
- Re-run the same unresolved-reason sample shape as Plan 010, or record why the
  exact sample cannot be repeated. Split unresolved calls by receiver,
  overload, supertypes, nested class body, missing method, static class-name
  receiver, unsupported declaration kind, and other reasons. Split unresolved
  references by no-source, source-root boundary, imports, supertype guard,
  ambiguity, unsupported construct, and stale/unavailable provider.
- Measure the addressable receiver subset on the same sample. For each
  receiver-qualified unresolved call, classify:
  - receiver expression shape: `this`, simple identifier, `new Type(...)`,
    class-name/static-looking receiver, chained/field receiver, or other;
  - whether the receiver type can be established from current covered evidence;
  - whether the referring class itself declares supertypes, so current
    `resolveType` would decline cross-unit receiver type evidence before the
    call target is considered;
  - whether the receiver type names a current top-level class, or instead an
    interface, enum, record, annotation, JDK/dependency type, or unsupported
    construct;
  - whether the receiver class declares supertypes;
  - whether exactly one method of the invoked name is declared in that class;
  - method access distribution: public, protected, package-private, private, or
    unavailable;
  - whether the invocation is inside a nested class body; and
  - whether source-root visibility permits the receiver type and method.
- Treat the interface/enum/record/annotation split here as an offline
  measurement classification, not as a product runtime reason. The current graph
  only exports Java classes across units, so cross-unit uncovered top-level type
  declarations are not distinguishable from "no current top-level class" unless
  ADR 009 explicitly admits a new minimal uncovered-type evidence channel.
- Compute the go/no-go addressable subset from a conservative public-method
  lower bound. Later ADR 009 decisions may expand the covered access subset, but
  they must not retroactively make the Stage 0 go decision depend on Stage 1.
- Measure the supertype-guard opportunity separately: count references that
  would need hierarchy evidence beyond this plan, and estimate how many have a
  source-available superclass chain with no interfaces or dependency/JDK gaps.
- State whether the Plan 011 product claim is now supported by an external
  latency observation, still supported only by local work bounds, or contradicted
  by measured work.

Done when:

- The progress log records the repository identity, baseline commands, results,
  quality counts, addressable receiver count, supertype opportunity estimate,
  and go/no-go verdict against the Start Rule.
- If the addressable receiver subset is below the threshold, the plan stops
  before ADR/code work and records either a revised plan direction or a
  follow-up.
- No Java semantic code has changed before this verdict.

### Stage 1: ADR For Java Receiver-Qualified Calls

Purpose: record the durable Java semantic decision before implementation.

Depends on: Stage 0 go.

Likely files:

- `docs/adr/009_java_receiver_qualified_calls.md`
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
  record of what was weighed, and a later plan asking why receiver resolution
  stops where it does would have to read this plan's git history instead of a
  decision record.
- Decide whether Java `CALLS` means static target only, and explicitly leave
  dynamic dispatch and overriding subtype analysis unrecorded.
- Decide whether receiver type evidence from parameters, locals, fields, and
  `new Type(...)` is internal frontend evidence or graph content. If it becomes
  graph content, amend this plan before implementation.
- Decide how class-shape evidence is established. This plan's proposed answer
  is additive Java extension labels on existing Java definitions, not
  provider-source re-reading by the Java projection.
- Decide whether uncovered top-level Java declaration kinds get any minimal
  evidence. This plan's proposed answer is no: same-unit non-class type
  declarations may produce a precise unsupported reason from current source, but
  cross-unit interfaces/enums/records/annotations remain indistinguishable from
  missing current class exports. If ADR 009 admits minimal cross-unit
  uncovered-type evidence instead, amend this plan before Stage 4.
- Decide the covered method-access subset, and state what happens to private,
  protected, package-private, and public methods outside that subset.
- State that build descriptors, cross-module visibility, inheritance entities,
  dispatch, overload resolution by argument type, `module`, and `IMPORTS` are
  not admitted.
- Name the fixture families Stage 2 and Stage 5 must satisfy.
- Own the Java semantic vocabulary it introduces, and record that ownership.
  Receiver type environment, binding introducer, shadow-only poison, covered
  access subset, and static target versus dispatch are ADR-owned normative
  terms, not glossary entries: `GLOSSARY.md` is not normative and must not
  restate them. Add or revise a glossary entry only for a term whose meaning is
  project-wide rather than Java-specific, such as class shape.

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

- Add committed fixture cases for receiver-qualified calls:
  - `this.m()` and `local.m()` to a unique declared method in a class with no
    supertypes;
  - parameter, local variable, field, and `new Type().m()` receiver shapes;
  - receiver type supplied by same unit, same source root, standard-layout
    test-to-main root, and single-type import;
  - unknown receiver, out-of-scope receiver class, duplicate local binding,
    overloads, target class with supertypes, nested class body, `super.m()`,
    `ClassName.staticLike()`, chained receivers, unsupported receiver type, and
    unresolved receiver type.
- Add shadowing fixtures for every binding-introducing Java node Stage 4 must
  treat as poison unless explicitly covered:
  - `enhanced_for_statement`;
  - `catch_formal_parameter`;
  - `resource`;
  - `lambda_expression` / `inferred_parameters`;
  - `type_pattern` and `record_pattern`;
  - `spread_parameter`;
  - `formal_parameter` or local declarators with `dimensions`.
- Add provider/class-shape edit cases:
  - target method added after an unresolved call;
  - target method removed after a fact;
  - target method overloaded after a fact;
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
- Stage 2 fixtures pin cases, not old reason strings. Stage 4 is expected to
  replace some unresolved explanations with more precise ones.

Done when:

- The fixture matrix exists with pre-implementation expectations for every case
  before behavior changes.
- Negative cases assert the applicable category and reason family, not just
  "no fact".
- The progress log contains the stage's risk matrix update and focused command
  results.

### Stage 3: Java Method Projection, Class Shape, And Invalidation

Purpose: add the candidate infrastructure needed for receiver calls, without
yet emitting new receiver-qualified call facts.

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
  root, declared-supertypes shape, covered method access, and current declared
  methods grouped by simple method name.
- Re-read graph facts for entities/methods and Java extension labels for class
  shape before answering. Hints may grow and over-invalidate, but they must not
  be authority.
- Preserve snapshot/query indexes from Plan 011. No relationship query path may
  scan every assertion to answer one receiver call.
- Add reader-hint storage and the `Upkeep` path that Stage 5 will populate for
  units that mention an exact receiver class and method name. The path must
  cover calls that are currently unresolved because the method is missing,
  overloaded, access-blocked, or blocked by class shape.
- Extend `Upkeep` so a class-shape change reanalyzes affected readers even when
  the previous relationship had no provider dependency because it was
  unresolved. Class shape for this plan includes method set, covered method
  access, and declared supertypes.
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
  covered access classification, source-root visibility, stale-provider
  rejection, class-shape change detection, and reader invalidation through
  seeded reader hints.
- Edit-history tests prove that changing one method or class-shape label
  reanalyzes only relevant hinted readers, not every declarer/importer in the
  package.
- Existing Java package/import tests still pass unchanged.
- `zig build test-mcp` passes. The new class-shape labels are MCP-visible:
  `extension.labels` is serialized into tool responses, so this stage changes
  payload content even though it changes no tool contract and emits no new call
  fact.
- No new Java receiver-qualified call fact is emitted by this stage.

### Stage 4: Exact Receiver Type Environment

Purpose: let the Java frontend know enough local static receiver types to make
Stage 5 possible without inventing bindings.

Depends on: Stage 3.

Likely files:

- `src/frontends/java.zig`
- focused tests/fixtures

Required behavior:

- Build a method-body receiver environment with lexical scoping and a closed
  covered binding list. Supported bindings are:
  - `this` as the enclosing class;
  - non-spread `formal_parameter` nodes with a simple class type that resolves
    exactly, no array/varargs dimensions, and no unsupported type shape;
  - `local_variable_declaration` declarators with a simple class type that
    resolves exactly, visible only after declaration and inside their lexical
    scope, with no variable dimensions;
  - class `field_declaration` names with simple class types, consulted only when
    no parameter, local, or shadow-only binding claims the name; and
  - `object_creation_expression` receiver expressions where the constructed
    type resolves as an exact current class under existing Java type rules.
- Treat every binding-introducing construct outside that covered list as a
  shadow-only poison in its lexical region, so field fallback and outer locals
  cannot produce a false receiver. The stage must cover at least the node kinds
  named in Stage 2's shadowing fixture list.
- Treat duplicate declarations in the same lexical scope, malformed
  declarations, generic/array/wildcard receiver types outside the covered shape,
  assignments, casts, method-return receivers, chained field access, `super`,
  class-name receivers, and lambda/local-class body interactions as unresolved.
- Keep nested class bodies as a boundary. A call inside a class body declared
  within a method is still analyzed as nested and does not borrow the outer
  method's receiver environment.
- Record distinct unresolved reasons for receiver type unknown, receiver type
  ambiguous, receiver type out of scope, receiver declaration kind unsupported,
  receiver expression outside covered shapes, and receiver type declared here
  but unsupported as interface/enum/record/annotation rather than top-level
  class.
- The interface/enum/record/annotation reason is required only when the current
  unit's own source proves the non-class declaration. For another unit, the
  current Java graph exports only classes; unless ADR 009 admits new uncovered
  top-level type evidence, a cross-unit non-class declaration remains the same
  reason family as "no current top-level class export/source".

Done when:

- The type environment can be tested without emitting receiver-qualified call
  facts.
- Fixture cases prove lexical shadowing, before-declaration use, duplicate
  bindings, field fallback, shadow-only poisoning, unsupported declaration-kind
  reasons, and source-root visibility.

### Stage 5: Receiver-Qualified Call Facts

Purpose: convert the measured receiver gap into exact Java `CALLS` facts where
the frontend has enough evidence.

Depends on: Stage 4.

Likely files:

- `src/frontends/java.zig`
- Java member projection files from Stage 3
- focused tests/fixtures

Required behavior:

- Resolve a receiver-qualified invocation to a fact only when all of these hold:
  - the receiver type environment establishes exactly one current Java top-level
    class;
  - the class is inside the ADR 008 visibility boundary;
  - the method projection finds exactly one current declared method of that name
    in the target class;
  - method access is inside the subset accepted by ADR 009;
  - the target class declares no supertypes;
  - the invocation is not inside a nested class body;
  - no overload, unsupported receiver shape, unsupported binding introducer, or
    unsupported class shape could change the target.
- Keep the full invocation text as the designator for unresolved qualified
  calls, as today.
- Declare provider dependencies for external receiver type and method provider
  units.
- Populate method/class-shape reader hints for exact receiver class and
  method-name pairs, including unresolved calls that could become facts after a
  provider method/class-shape change.
- Record distinct unresolved reasons for missing method, overloaded method,
  inaccessible method outside the covered subset, target class has supertypes,
  receiver out of scope, unsupported receiver declaration kind, and unsupported
  receiver expression.
- Re-run Stage 2 fixtures with expected facts enabled for covered positive
  cases and expected unresolved reason families for every negative case.

Done when:

- Covered receiver-qualified calls become `CALLS` facts in committed fixtures.
- Every negative case remains unresolved with an exact reason family.
- Provider method add/remove/overload/access edits reanalyze the caller and
  change only the affected claim.
- Provider class-shape edits, especially adding a declared supertype after a
  fact, reanalyze the caller and remove stale facts from default current
  queries.
- Focused counters show lookup work bounded by candidate tables, not by all
  Java units or all graph assertions per invocation.
- Dependency declaration count, propagation rounds, and propagation exhaustion
  are recorded.

### Stage 6: Supertype Guard Reassessment And Follow-Up

Purpose: decide whether the supertype-driven reference gap deserves its own
future plan after receiver calls land.

Depends on: Stage 5.

Likely files:

- `docs/reports/012_java_semantic_quality_without_query_regression_progress.md`
- optional follow-up under `docs/followups/`

Required behavior:

- Re-run the Stage 0 unresolved-reference sample after Stage 5. Record whether
  the supertype guard is still the dominant in-working-copy reference gap and
  give concrete examples.
- Record the addressable closed-hierarchy subset separately from the full
  supertype bucket:
  - every superclass in the chain would have to resolve to a current Java class
    inside the ADR 008 visibility boundary;
  - no interface or unknown/non-class supertype may keep the hierarchy open;
  - cycles would have to be detected;
  - member type declarations with the referenced name would have to be checked
    through the reachable hierarchy; and
  - any unsupported member type, missing provider, stale provider, or out-of-
    scope provider would keep the current unresolved answer.
- Do not implement this relaxation in Plan 012.
- Create a follow-up only if the measured subset is large enough to justify a
  dedicated plan. As a default threshold, record a follow-up when the subset is
  at least 50 references in the sample or at least 1% of sampled outgoing
  claims, whichever is smaller; otherwise record that the risk is not justified
  by current evidence.

Done when:

- The progress log records why the supertype guard stays unchanged in Plan 012.
- Any follow-up created has exact acceptance direction, required tests, and
  explicit class-shape/invalidation requirements.

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

- Re-run the Stage 0 external probe and compare:
  - exact call facts and unresolved reasons;
  - exact reference facts and unresolved reasons;
  - `semidx_health`, `semidx_references`, and `semidx_context depth=2` work
    shape and wall-clock observations;
  - cold index, no-op refresh, one-file refresh, provider-method-change refresh,
    and provider-class-shape-change refresh work;
  - dependency declaration count, propagation rounds, and propagation
    exhaustion;
  - memory impact of new projection tables and new Java extension labels where
    measured. On apache/dubbo, report label overhead against the observed class
    and method counts and the Plan 010 371 MB baseline; on a substitute sample,
    report the substitute's counts instead;
  - response-size impact of the new labels: bytes per Java definition item at
    `detail=full`, and whether any habit-loop call now exhausts its budget or
    needs more pages than the Stage 0 baseline at the same
    `max_response_bytes`. Budget semantics are unchanged; what the same budget
    now fits is an observation this plan owes its consumers.
- Compare receiver-call results against the Stage 0 addressable subset. The
  denominator is the measured subset under the access subset ADR 009 accepted.
  If ADR 009 accepts more than public methods, Stage 7 must recalculate that
  denominator and record both the public lower-bound and accepted-access counts.
  The plan is not complete unless at least the Stage 0 go-threshold count and at
  least 80% of the accepted-access measured subset become exact `CALLS` facts in
  the same sample. If the 80% bar is missed, closure is allowed only when every
  miss has a recorded out-of-subset reason; otherwise reopen the plan.
- Update the capability matrix and preview reference with the exact covered Java
  receiver cases and the cases left unresolved, including static target versus
  dispatch, access subset, receiver declaration-kind limits, class-shape labels,
  and class-shape limits.
- Update `SPEC.md` where this plan moved requirements it owns: name the new Java
  receiver/member class-shape invalidation producer and Java extension labels,
  or explicitly record why those owner rows do not change.
- Update the Java capability matrix definition-label and "Not recorded" rows so
  `java.supertypes`, method access labels, and the remaining inheritance and
  dispatch exclusions do not contradict each other.
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

- The external remeasurement shows at least the Stage 0 go-threshold count and
  at least 80% of the accepted-access measured subset as new exact Java receiver
  call facts in the covered cases. If the 80% bar is missed, every miss has a
  recorded out-of-subset reason; otherwise the plan is reopened before closure.
- No new approximate assertions are introduced.
- Plan 011's anchored query work bound still holds.
- Dependency propagation does not silently leave current stale facts behind; any
  exhaustion is reported and treated as residual risk.
- Documentation states the exact capability boundary without broad Java claims.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Durable Java `CALLS` semantics are authorized | Plan implements a new semantic relationship without an ADR | ADR plus plan gate | ADR 009 answers all eight constitutional questions | ADR rejects or changes the proposed rule, requiring plan amendment | Stage 1 ADR and progress log |
| Receiver-qualified facts are exact | False `CALLS` facts from guessed receiver or method target | Java fixture/golden plus frontend integration | Covered receiver shapes resolve to one current method | Unknown receiver, overload, supertypes, out-of-scope type, nested class body | Stage 5 fixture tests and progress-log counts |
| Receiver bindings are safe | Uncovered binding introducer shadows a field/local but frontend still resolves | Fixture/golden | Covered binding list and shadow-only poison rules | for-each, catch, resource, lambda, pattern, varargs, dimensions | Stage 2/4 fixtures |
| Intermediate evidence stays honest | Parameter/local types silently become graph facts or unsupported evidence becomes authority | ADR plus fixture/golden | ADR decides internal evidence versus emitted references | ADR requires emitted references, forcing plan amendment | Stage 1 ADR, Stage 4 fixtures |
| Unresolved remains distinguishable | Unsupported, unavailable, ambiguous, and inaccessible cases look alike | Fixture/golden | Each decline reason family appears in graph output | No-source, out-of-scope, inaccessible, overloaded, duplicate local, unsupported declaration kind | Stage 2 and Stage 5 negative fixtures |
| Incremental freshness holds | Caller stays stale after provider method/class-shape change | Focused integration/edit-history test | Provider method/class-shape change reanalyzes affected readers | Fact becomes unresolved after provider adds `extends`; unresolved becomes fact after method appears | Stage 3/5 edit tests |
| Query speed is preserved | Per-call lookup scans all units/assertions | Test-only work counters plus external observation | Candidate work grows with receiver/method candidates, not repository size | Old full-scan path fails the bound | Stage 0/5/7 work measurements |
| Write path stays bounded | Method/class-shape reader hints cause repository-wide reanalysis | Synthetic doubled-corpus integration test | Provider change reanalyzes readers, not all units | Unit stops reading a method but remains hinted as harmless superset; editing one method does not reanalyze unrelated package declarers/importers | Stage 3/7 refresh measurements |
| Dependency propagation stays useful | New cross-unit call dependencies exceed propagation budget or make propagation too costly | Integration and scale/work test | Declaration count, rounds, and exhaustion recorded | Chain over 64 rounds emits `analysis_unavailable` and residual risk | Stage 0/5/7 measurements |
| Source-root boundary remains intact | Receiver/type/method lookup crosses modules by name | Fixture/golden | Same root and test-to-main resolve; other roots unresolved | Cross-module same package with no admitted dependency | ADR 008 fixtures reused in Stage 3/5 |
| Method access is not guessed | Private/protected/package-private method becomes cross-unit fact without proof | Fixture/golden | Covered access subset is enforced | Private method in another class, protected method outside covered subset | Stage 1 ADR and Stage 5 fixtures |
| Public contracts unchanged | MCP clients see shape drift | MCP tests/runtime smoke | Existing tool schemas and payload families still pass | New Java facts through existing relationship fields only | `zig build test-mcp`, `zig build preview-gate` |
| Capability docs stay honest | Docs imply broad Java receiver or dispatch support | Documentation review | Matrix names exact receiver cases and exclusions | Cross-module, overload, unknown hierarchy, classpath, dynamic dispatch left unresolved | Stage 7 doc diff |

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
constitution, ADR 003, ADR 004, ADR 006, ADR 008, Follow-up 011, Follow-up 012,
Plan 010 progress, Plan 011 progress, `SPEC.md`, `CORE.md`, `MEMORY.md`,
`GLOSSARY.md`, the capability matrix, the adoption strategy, and the current
Java frontend.

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

- the post-Plan-011 external Java baseline and addressable receiver subset are
  recorded;
- ADR 009 is accepted and every later stage follows it;
- receiver-qualified calls in the covered subset become exact facts at or above
  the Stage 0 go-threshold count, and either at least 80% of the
  accepted-access measured addressable subset becomes exact or every miss below
  the 80% bar has a recorded out-of-subset reason;
- unsupported, ambiguous, stale, out-of-scope, inaccessible, overloaded, and
  open-hierarchy cases remain unresolved with distinct reason families;
- provider method and class-shape changes maintain freshness incrementally;
- query, write-path, and dependency-propagation work bounds show no regression
  from Plan 011's indexed access model;
- the supertype guard is either left unchanged with measured rationale or split
  into a follow-up with precise acceptance direction;
- capability docs and `MEMORY.md` describe the new Java boundary honestly; and
- every stage's verification, skipped checks, and residual risk are recorded in
  the progress log.
