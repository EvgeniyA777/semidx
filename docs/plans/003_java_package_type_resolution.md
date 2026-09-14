---
title: "Java package type resolution"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "execute_when_requested"
updated: "2026-09-14"
---

# 003: Java Package Type Resolution

## Goal

Add the first production cross-unit semantic evidence producer: Java
same-package, top-level type resolution. A Java source unit that names a simple
type declared by exactly one current top-level class in the same explicit Java
package records a `REFERENCES` fact targeting that class definition, declares
the provider source unit it read, and is reanalyzed when that package binding
changes.

The companion progress log is
[docs/reports/003_java_package_type_resolution_progress.md](../reports/003_java_package_type_resolution_progress.md).
The governing ADR is
[ADR 004](../adr/004_allow_java_same_package_type_resolution.md).

## Scope

- Resolve unqualified Java type references to top-level Java class definitions
  in other source units of the same explicit package.
- Keep Java package information in Java extension vocabulary and analyzer
  context. Do not create package, module, or import graph entities.
- Allow frontend batches to target graph-established external entities supplied
  by analyzer context, without letting frontends allocate graph identity.
- Record unit-to-unit dependencies for resolved cross-unit references.
- Invalidate Java units when the current top-level class export set for their
  explicit package changes.
- Update the repository-scale Java fixture expectations that currently prove
  `Helper` remains unresolved.
- Preserve Clojure behavior and all same-unit Java behavior.

## Non-Scope

Do not admit `module` or `IMPORTS`, publish a semantic contract version, create
a capability matrix, add a public API, or introduce persistence, daemon mode,
file watching, vectors, embeddings, RAG, MCP, HTTP, or a consumer surface.

Do not implement Java imports, wildcard imports, static imports, fully qualified
name resolution, default-package cross-unit resolution, nested classes, local or
anonymous classes, classpath or dependency-jar symbols, inheritance, overloads,
receiver typing, method dispatch, fields as definitions, or Clojure namespace
resolution.

Do not use repository-wide name matching as a graph assertion. A type target is
a fact only when it satisfies [ADR 004](../adr/004_allow_java_same_package_type_resolution.md).
Ambiguous and unsupported cases stay unresolved or diagnosed.

Do not redesign snapshots or storage. The current in-memory `Snapshot` and
graph mutation model remain in force.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  §1, §3, §5, §6, §7, and §8.
- [ADR 003](../adr/003_reject_name_match_assertions.md) rejects name matching
  and identifies language-correct scoping as the legitimate path.
- [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) permits the
  narrow Java same-package type producer.
- [SPEC.md](../../SPEC.md) owns requirements, invalidation, coverage, and future
  publication work.
- [CORE.md](../../CORE.md) owns the accepted unversioned roster:
  `repository`, `file`, `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and
  `CALLS`.
- [CONFORMANCE.md](../../CONFORMANCE.md) owns scenario families for graph
  authority, knowledge categories, incrementality, core and extensions, honest
  degradation, and local operation.
- [MEMORY.md](../../MEMORY.md) owns current implementation reality and near-term
  priorities.

## Current Implementation Context

- `src/frontends/java.zig` already reads package declarations and stores
  `java.package` extension labels on class and method definitions.
- `emitTypeReference` resolves Java type names only against classes declared in
  the same source unit; otherwise it records an unresolved designator.
- `src/core/contract.zig` has `DraftTarget.local` and `DraftTarget.designator`,
  but no way for a frontend batch to target an already-established graph entity
  from another unit.
- `src/core/dependencies.zig` and `Index.propagateInvalidation` already support
  unit-to-unit dependency propagation, but no production frontend declares a
  dependency.
- `tests/vertical_slice_test.zig` currently proves the repository-scale Java
  `Helper` reference stays unresolved. This test becomes the visible acceptance
  point for the new producer.

Semantic Code Indexing was required by repository policy. No callable semidx MCP
tools were available through tool discovery in this environment (`create_index`
was not exposed), so this plan used targeted direct inspection of the files
listed above.

## Plan-Level Decisions

**Java package context is a projection, not a graph model.** The analyzer may
build a temporary Java package binding table from current graph facts. The table
does not create entities or relationships and has no authority beyond selecting
the current candidate a Java frontend can validate under ADR 004.

**External targets are graph ids supplied by context.** A frontend still never
allocates identity. It may target an external entity only when the analyzer gave
it that entity id with provider-unit evidence. Reconciliation validates that the
external target is live, current, and compatible with the relationship kind.

**Ambiguity is unresolved, not approximate.** If two current top-level class
definitions share the same explicit package and simple name, no cross-unit fact
is recorded. The unresolved assertion should name ambiguity in its explanation.

**Package export changes invalidate by package.** Provider-unit dependencies
handle already-resolved references, but they cannot update a dependent whose
previous reference was unresolved because no provider existed. Therefore an add,
remove, class rename, or package change that changes a Java package's exported
top-level class set reanalyzes other live Java units in that explicit package.

**Unrelated packages remain unaffected.** Reanalysis may be coarse inside one
package for this first implementation, but it must not become repository-wide
work for a package-local export change.

## Architecture Boundaries

1. `core/contract`
Responsibility: allow a frontend batch to name a graph-established external
target and to carry dependency declarations.
Does not know about: Java packages, imports, or repository lookup policy.

2. `core/reconcile`
Responsibility: integrate local, external, and designator targets without
weakening resolution validation, freshness filtering, or identity preservation.
Does not know about: Java scoping rules.

3. `frontends/root` / `Analyzer`
Responsibility: build analyzer context from current graph state, choose the
frontend, and schedule reanalysis for scan and invalidation events.
Does not know about: Java grammar internals beyond invoking the Java frontend
and building its context from graph facts.

4. `frontends/java`
Responsibility: apply the narrow Java same-package top-level type rule, emit
facts only for unique current same-package providers, and leave every other
case unresolved or diagnosed.
Does not know about: filesystem scanning, graph allocation, consumer protocols,
or shared-core admission.

5. `core/graph`
Responsibility: expose the smallest query helpers the analyzer needs to build
current Java package bindings and validate external targets.
Does not know about: parsing or import semantics.

6. `tests` and `fixtures/repository-scale`
Responsibility: make cross-unit resolution, invalidation, ambiguity, and
non-regression observable through published snapshots and measured frontend
invocation counts.

## Stages

### Stage 1: Context And External Target Contract

Purpose: let a frontend resolve to graph-established entities outside its own
batch while preserving the rule that frontends never allocate identity.

Likely files:

- `src/core/contract.zig`
- `src/core/reconcile.zig`
- `src/core/graph.zig`
- `src/frontends/root.zig`
- core tests in `src/core/{contract,reconcile,graph}.zig`

Required behavior:

- Add an external entity target variant to the draft relationship path.
- Validate during integration that an external target names a live current
  entity, and that `DEFINES` still cannot target non-definitions.
- Keep unresolved designators structurally distinct from entity targets.
- Preserve existing local-target behavior and same-unit identity preservation.
- Provide a minimal analyzer context path that can be empty for Clojure and for
  Java tests that do not need repository context.

Done when:

- Core tests prove external targets integrate as facts only when valid.
- Existing vertical-slice tests still pass before Java cross-unit behavior is
  changed.
- `zig build test-core --summary all` passes.

### Stage 2: Java Package Binding Context

Purpose: build the narrow repository context Java needs without admitting
`module` or `IMPORTS`.

Likely files:

- `src/frontends/root.zig`
- `src/frontends/java.zig`
- `src/core/graph.zig`
- focused frontend tests in `src/frontends/root.zig` or
  `tests/vertical_slice_test.zig`

Required behavior:

- Build a current Java binding table keyed by explicit package plus top-level
  class name.
- Include only current fact definitions produced by the Java frontend whose
  identity role is `class`.
- Track the provider `SourceUnitId` for each binding.
- Mark duplicate package/name bindings ambiguous instead of choosing one.
- Keep default-package cross-unit resolution out of scope.

Done when:

- A unit with no repository context behaves exactly as before.
- A unit with a unique same-package provider can receive that provider in
  context.
- Ambiguous same-package providers are visible to the Java frontend as
  ambiguous, not as a chosen target.
- `zig build test-core --summary all` passes if graph helpers changed.

### Stage 3: Java Cross-Unit Type Resolution

Purpose: turn the context into the first real production cross-unit graph fact.

Likely files:

- `src/frontends/java.zig`
- `tests/vertical_slice_test.zig`
- `fixtures/repository-scale/java/demo/*.java`
- `fixtures/repository-scale/README.md`

Required behavior:

- Resolve a simple type name to a same-package external class when ADR 004's
  conditions are met.
- Record the target as a `REFERENCES` fact and record a dependency on the
  provider source unit.
- Leave same-unit references as local facts.
- Leave missing, cross-package, default-package, qualified, and ambiguous names
  unresolved with explanations that identify the reason.
- Do not create approximate assertions.

Done when:

- The repository-scale Java `Helper` reference resolves to the `Helper` class
  entity as a fact.
- The repository-scale Clojure `decorate` reference still stays unresolved.
- Existing same-unit Java and Clojure tests still pass.
- `zig build test --summary all` passes.

### Stage 4: Package Export Invalidation

Purpose: keep cross-unit facts current when package bindings appear, disappear,
or retarget.

Likely files:

- `src/root.zig`
- `src/frontends/root.zig`
- `src/core/graph.zig`
- `tests/vertical_slice_test.zig`
- generated temporary test trees inside tests

Required behavior:

- Capture Java top-level package exports before and after a scan.
- When an explicit package's exported top-level class set changes, reanalyze
  other live Java units in that package, excluding units already analyzed by
  their own content change.
- Provider-unit dependency propagation still works for already-resolved
  cross-unit facts.
- A package-local export change must not reanalyze Clojure units or Java units
  in unrelated packages.
- A direct implementation-body edit that does not alter top-level class exports
  must not force package-wide reanalysis unless the existing coarse dependency
  mechanism reaches a dependent because that dependent read the provider unit.

Done when:

- Adding a same-package provider changes a previously unresolved type reference
  into a fact without editing the dependent unit.
- Removing or renaming the provider changes the dependent back to unresolved or
  to the new unique provider, with stale facts excluded from default queries.
- A provider-unit edit reaches its dependent through dependency propagation.
- A package export change in `demo` does not reanalyze unrelated package units.
- Measured frontend invocation counts prove the work is package-scoped, not
  repository-wide.
- `zig build test --summary all` passes.

### Stage 5: Documentation, Review, And Closure

Purpose: synchronize the source-of-truth documents and leave a clean handoff.

Likely files:

- `MEMORY.md`
- `SPEC.md`
- `CONFORMANCE.md`
- `docs/reports/003_java_package_type_resolution_progress.md`
- possibly `CORE.md` only if implementation evidence changes admission text

Required behavior:

- Record what now exists: Java same-package top-level type references can be
  cross-unit facts under ADR 004.
- Record limitations: no `module`, no `IMPORTS`, no published contract, no
  capability matrix, and no general Java support claim.
- Record exact verification commands and residual risks.
- Run a findings-first review of the final diff with
  `semidx-code-review`.

Done when:

- Documentation and tests agree about current runtime behavior.
- Progress log marks all stages completed with verification evidence.
- `MEMORY.md` near-term priorities move past this workstream.
- `zig build test-core -Dgrammars-dir=/nonexistent --summary all`,
  `zig build test --summary all`, `zig fmt --check build.zig src tests`,
  `./scripts/check-agent-attribution.sh --all`, and `git diff --check` pass or
  skipped checks are recorded with reasons.

## Stop Conditions

- Stop before code if implementing Stage 1 appears to require a package or
  module entity in the shared core. That is a `CORE.md` admission plan, not this
  plan.
- Stop before recording a fact if the producer cannot distinguish language
  scoping from a string match. Leave the relationship unresolved.
- Stop before widening Java coverage beyond top-level same-package type names.
  Imports, classpath symbols, nested classes, and method dispatch need their own
  requirements.
- Stop if package-export invalidation can only be implemented by reanalyzing the
  whole repository for every Java package change. Revise the plan before
  continuing.

## Risk Matrix

| Risk | Lowest sufficient proof |
| --- | --- |
| Name matching sneaks back in as graph authority | Fixture with same simple name in a different package stays unresolved |
| Ambiguity is silently resolved | Fixture with duplicate same-package providers records no fact |
| Frontend allocates or invents graph identity | Contract/reconcile test rejects invalid external target ids |
| Unresolved targets become indistinguishable from facts | Existing model tests plus new unresolved ambiguity fixture |
| Added provider leaves dependent stale as unresolved | Rescan test adds provider without editing dependent and observes a new fact |
| Removed or renamed provider leaves stale fact current | Rescan test removes/renames provider and default queries exclude the old fact |
| Cross-unit dependency never triggers | Provider edit increments `invalidated` and reanalyzes the dependent |
| Package invalidation becomes repository-wide | Invocation-count test with unrelated package and Clojure units |
| Core roster widens accidentally | Assertions check zero `IMPORTS`, no `module` entities, and zero approximate assertions |
| Core gains parser or filesystem dependency | `zig build test-core -Dgrammars-dir=/nonexistent --summary all` |

## Verification Commands

Run focused commands during the relevant stage, then the full lane at closure:

```sh
zig build test-core --summary all
zig build test-core -Dgrammars-dir=/nonexistent --summary all
zig build test --summary all
zig build run -- fixtures/repository-scale
zig fmt --check build.zig src tests
./scripts/check-agent-attribution.sh --all
git diff --check
```

`zig build run -- fixtures/repository-scale` is observational only. Do not
assert against its text output as a public contract.

## Plan Readiness Gate

Applied on 2026-09-14 against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate).

### Hard Fail Conditions

| Condition | Result |
| --- | --- |
| Product or runtime behavior unclear, or conflicting with sources of truth | Pass. ADR 004 gives the narrow permission; ADR 003 remains the rejection of name matching. |
| Scope boundaries missing, vague, or allowing unrelated refactoring | Pass. Imports, modules, public contracts, persistence, Clojure resolution, classpath symbols, and dispatch are explicitly non-scope. |
| A key technical decision implicit, unjustified, or externally gated without a stop rule | Pass. The external-target contract, Java projection context, ambiguity behavior, and package invalidation rule are named decisions; stop rules cover accidental module admission and repository-wide invalidation. |
| Branches mentioned but not carried through stages, files, verification, and DoD | Pass. Ambiguous, missing, cross-package, provider addition, provider removal, and unrelated package branches all have stage coverage. |
| Stages depending on later stages, or lacking concrete outputs | Pass. Stage 1 enables external targets, Stage 2 builds context, Stage 3 records facts, Stage 4 maintains them incrementally, Stage 5 closes docs. |
| DoD not verifiable through files, commands, tests, or artifacts | Pass. Every DoD item is observable through tests, snapshot queries, invocation counts, docs, or exact commands. |
| Test strategy missing main risks | Pass. The risk matrix covers authority, ambiguity, identity, resolution, freshness, invalidation, package scope, core-roster drift, and core isolation. |
| Runtime constraints ignored | Pass. The plan preserves local operation, no network, no new service, and the existing Zig/tree-sitter lanes. |
| Documentation targets contradict each other or carry stale bookkeeping | Pass. ADR 004, this plan, MEMORY, and report 003 point to the same workstream without changing accepted CORE meanings. |
| Requires guessing what to implement, skip, test, or when to stop | Pass. Scope, non-scope, staged outputs, stop conditions, and verification commands are explicit. |

### Ready Criteria

| Criterion | Result |
| --- | --- |
| Contract changes explicit and tied to sources of truth | Pass. External targets are scoped to the frontend batch contract and ADR 004. |
| Scope and non-scope explicit | Pass. |
| Key decisions and rationale recorded | Pass. |
| Blockers and branches have precise stop and resume behavior | Pass. |
| Each stage has purpose, ordered dependencies, and concrete outputs | Pass. |
| Verification commands and acceptance checks named | Pass. |
| DoD observable and falsifiable | Pass. |
| Risk-based tests mapped to behavior | Pass. |
| Runtime and environment traps considered | Pass. |
| Internally consistent and not overloaded with irrelevant detail | Pass. |

**Gate result: ready for execution.**
