---
title: "Repository-scale ingestion and the source-unit registry"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 002: Repository-Scale Ingestion And The Source-Unit Registry

## Goal

Make the graph maintainable over a repository rather than over a hand-written
list of files: discover source units, give them identity that survives a rename,
reconcile a rescan against the existing graph, and prove that an edit reanalyzes
the affected region and nothing else.

This is the layer [ARCHITECTURE_CONSTITUTION.md §5](../../ARCHITECTURE_CONSTITUTION.md#5-incrementality-is-core)
describes and the first slice could not exercise: with two manually registered
units there is no repository to grow, no rename to survive, and no unrelated
work to avoid.

Its companion progress log is
[docs/reports/005_repository_scale_ingestion_progress.md](../reports/005_repository_scale_ingestion_progress.md).

## Why This Before `module` And `IMPORTS`

`module` and `IMPORTS` are the two blocked candidates in
[CORE.md](../../CORE.md#admission-status). Admitting them requires evidence that
a cross-unit availability question is well-posed and answerable, and that
availability changes invalidate what depended on them.

None of that is observable today. Every reference either resolves inside its own
unit or stays a designator, so there are no cross-unit assertions, nothing to
invalidate, and no way to tell a correct invalidation rule from a rule that never
runs. Admitting `IMPORTS` against that would be admitting a paper model.

This plan builds the ground those questions stand on. It deliberately does not
admit either kind.

## Scope

- Discover source units under a declared root, by language, without a manual
  list.
- Register units with graph-allocated identity that is not their path.
- Detect, on a rescan, which units are unchanged, changed, added, removed, or
  renamed, and preserve identity where correspondence is established.
- Make a source unit's path a property of the unit rather than the scope that
  entity identity is derived from, so renaming a file does not destroy the
  identity of everything inside it.
- Reanalyze only units whose contents changed, and make that measurable rather
  than assumed.
- Track which units an analysis result depends on, so an invalidation rule has
  something to act on.
- Record cross-unit resolution candidates as approximate assertions, under the
  decision gate in Stage 5.
- Apply local budgets that keep a directory walk and a rescan from behaving
  pathologically, and report a unit that exceeds one instead of skipping it.

## Non-Scope

Do not implement persistence, public contracts or schemas, MCP, HTTP, any
consumer surface, vectors, embeddings, RAG, concurrency, daemon mode, background
file watching, or IDE integration.

Do not admit `module` or `IMPORTS`, and do not add a core kind. If this work
appears to need one, that is a requirements change for `CORE.md` and `SPEC.md`
under their own lifecycle, not a task inside this plan.

Do not implement import, package, or namespace resolution for any language. The
cross-unit work in Stage 5 is a name-match candidate recorded as approximate; it
is deliberately not an import model, and it must not be described as one.

Do not redesign snapshot representation or publication. `Snapshot` copying the
observable state per publish is a known cost recorded as risk here; changing it
is the storage-and-snapshots item owned by [SPEC.md](../../SPEC.md#requirements-still-to-specify).

Do not parse ignore files such as `.gitignore`. Exclusion is a configured deny
list in this plan.

Do not claim published language coverage, a capability matrix, or a semantic
contract version. Fixture and repository-scale evidence here is evidence, not a
support claim.

Do not optimize for speed. The budgets in scope exist to prevent accidental
quadratic or unbounded behavior, not to reach a performance target.

## Assumptions

- Zig 0.16 and the local tree-sitter dependencies remain as
  [ADR 002](../adr/002_local_tree_sitter_parser_dependency.md) fixed them.
  Directory walking uses `std.Io.Dir`; nothing here needs a new dependency.
- The accepted core roster is `repository`, `file`, `definition`, `CONTAINS`,
  `DEFINES`, `REFERENCES`, and `CALLS`, unversioned and unpublished
  ([report 003](../reports/003_core_admission_review.md),
  [report 004](../reports/004_defines_contains_split.md)). This plan uses them
  and changes none of their meanings.
- Freshness stays a separate axis from resolution
  ([report 002](../reports/002_slice_freshness_followup.md)). Repository-scale
  work adds units that can be stale independently; it does not change the rule.
- The two fixture frontends stay fixture-scoped. This plan does not widen Java
  or Clojure coverage, and a frontend change that is not required by the unit
  registry is out of scope.
- Tests may create temporary directory trees. They must clean them up and must
  not read or write outside them.

## Source Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) owns the
  non-negotiable architecture. §2 (entities, not chunks), §4 (identity across
  edits, naming file rename explicitly), §5 (incrementality and consistent
  observation), and §8 (local operation) are the clauses this plan is about.
- [SPEC.md](../../SPEC.md) owns changing requirements, including the source
  identity and invalidation items this plan advances but does not close.
- [CORE.md](../../CORE.md) owns the roster and admission state.
- [CONFORMANCE.md](../../CONFORMANCE.md) owns the scenario families. Stable
  identity, Incremental maintenance, Consistent observation, and Honest
  degradation are the ones this plan supplies evidence for.
- [MEMORY.md](../../MEMORY.md) owns current implementation reality.
- [Report 001](../reports/001_zig_vertical_slice_progress.md) and
  [report 002](../reports/002_slice_freshness_followup.md) own what the first
  slice actually built and what it left as risk.

## Plan-Level Decisions

**A source unit's identity is not its path.** The registry allocates it, the same
way the graph allocates entity identity. Path becomes a property of the unit,
carried and refreshed like a range. This is the same correction the model already
applies to entities: a location is evidence, not an identity. It is what makes
§4's "renaming a file" expressible at all.

**Entity identity scope becomes the unit's identity, not the unit's path.**
`IdentityEvidence.scope` currently holds a path string, so every definition in a
renamed file loses correspondence. After this change a rename moves one property
on one unit and leaves every entity inside it untouched.

**Unit correspondence is evidence-based and reuses the existing vocabulary.** A
rescan produces the same four identity events as entity reconciliation —
preserved, created, removed, lost — with the same rule that a break must be
visible as a break.

**Rename correspondence is established only by identical content.** A file that
moved and changed in the same rescan is recorded as removal plus creation, with
identity loss, not as a guessed rename. Guessing a rename from similar content is
a similarity heuristic; this plan does not make one. Recording it as a fact would
be exactly what §4's last sentence forbids.

**Unchanged units are not reanalyzed, and that is measured, not asserted.** The
analyzer counts frontend invocations; a rescan with one changed unit must invoke
a frontend once regardless of how many units exist.

**Discovery lives outside the shared core.** `src/core/` must not learn about
filesystems, directory walking, or file extensions. A new `src/source/` module
owns discovery and holds the only I/O in the ingestion path, so
`zig build test-core` keeps proving the core has no environment dependency.

**Budgets are honest, not silent.** A file larger than the size budget, a tree
deeper than the depth budget, or a scan larger than the unit budget produces a
diagnostic naming the limit. Nothing is skipped without a record.

**Ids are never reused.** A removed unit tombstones, like a removed entity, so a
later unit cannot inherit a previous unit's identity.

## Architecture Plan

### Boundaries

1. `source/discovery`
Responsibility: walking a declared root, deciding which files are source units of
which language, reading their contents, applying inclusion, exclusion, and
budgets, and producing a scan.
Knows about: the filesystem, path syntax, language-to-extension mapping, and
budget policy.
Does not know about: the graph, entities, assertions, reconciliation, or
frontends.
Why this boundary exists: the shared core must stay free of environment
dependencies, and `zig build test-core` must keep proving it.

2. `source/registry`
Responsibility: the set of known source units, their allocated identity, their
content identity, their current path and language, and the correspondence between
one scan and the next.
Knows about: scans, unit identity evidence, and unit identity events.
Does not know about: how a scan was produced, or what any frontend found.
Why this boundary exists: unit identity is the thing renames must survive, and it
must be decidable without reading a parse tree or a graph assertion.

3. `core/graph` (existing, extended)
Responsibility: additionally holds unit records keyed by allocated identity
rather than by position, supports unit removal, and exposes unit identity events
alongside entity identity events.
Knows about: what it already knows, plus unit tombstones.
Does not know about: discovery, paths as identity, or scan mechanics.
Why this boundary exists: the graph remains the authority for what a consumer
observes, including what happened to a unit.

4. `core/reconcile` (existing, extended)
Responsibility: additionally reconciles a scan against the registry and the
graph, deciding which units need reanalysis and what happens to the entities of a
unit that was removed or lost.
Knows about: scans, registry correspondence, and frontend batches.
Does not know about: the filesystem or parser internals.
Why this boundary exists: incrementality is core behavior, and the decision of
what to reanalyze belongs next to the decision of what to preserve.

5. `core/dependencies`
Responsibility: recording what an analysis result depended on beyond its own
unit, and answering which units an observed change invalidates.
Knows about: unit identity and the dependency records frontends declare.
Does not know about: import semantics, language scope rules, or what a
dependency means to a program.
Why this boundary exists: invalidation must be expressible before any
cross-unit semantics are admitted, and it must not smuggle `IMPORTS` in as an
implementation detail.

6. `fixtures/repository-scale`
Responsibility: multi-unit source trees and rescan histories large enough that
"only the affected region was reanalyzed" is a falsifiable claim.
Knows about: fixture source text and expected scan outcomes.
Does not know about: production repository layouts.
Why this boundary exists: the property this plan exists to prove is invisible at
two units.

### Contracts

1. `SourceScan`
Client: the registry and the reconciler.
Shape: the root it was taken under, the discovered units (path, language,
contents, content identity), the diagnostics discovery produced, and the budgets
in force.
Variation strategy: a value produced by `source/discovery` and consumed by
`source/registry`; a test may construct one directly, which is how the registry
stays testable without touching a filesystem.

2. `UnitIdentityEvidence`
Client: the registry.
Shape: current path, language, and content identity. It is evidence for
correspondence between scans, not the unit's id.
Variation strategy: a direct struct. Correspondence rules are a function over it,
so a stronger rule later is a change to one function rather than to every caller.

3. `ScanReconciliation`
Client: the ingestion driver and tests.
Shape: per unit, which of preserved, created, removed, or lost applies, and
whether reanalysis is required. Aggregate counts for the assertions tests make.
Variation strategy: a returned value, like `reconcile.Outcome`.

4. `AnalysisDependencies`
Client: the invalidation rule.
Shape: what a unit's analysis depended on outside itself, recorded by the
producer that depended on it.
Variation strategy: declared by a frontend batch. A frontend that declares
nothing is analyzed in isolation, which is the current behavior and stays valid.

### Dependency Direction

- `source/discovery` depends on the standard library and, from `core/model`, on
  value vocabulary only: `Language` and `DiagnosticKind`. It must not depend on
  `core/graph`, `core/contract`, or `core/reconcile`. An earlier draft of this
  line said "nothing in `core/`", which contradicted Stage 1's requirement of one
  extension-to-language table shared with `languageForPath` and would have forced
  a second `Language` enum that is guaranteed to drift. The property being
  protected is the other direction, and it is unchanged.
- `source/registry` depends on scan values and on `core/model` identity types.
- `core/graph`, `core/reconcile`, and `core/dependencies` depend on `core/model`
  and on each other as they already do.
- Nothing in `core/` depends on `source/discovery`.
- The ingestion driver in `src/root.zig` depends on all of them.
- `zig build test-core` continues to build and test `src/core/` alone.

## Implementation Sequence

### Stage 1: Source Discovery

Purpose: replace the manual unit list with a walk of a declared root, with the
policy and the budgets explicit.

Tasks:

- Add `src/source/discovery.zig` producing a `SourceScan` from a root path.
- Map file extensions to languages through one table, shared with
  `languageForPath`.
- Apply an exclusion deny list of directory names, defaulting to at least the
  build and tooling directories this repository already ignores.
- Apply budgets: maximum file size, maximum unit count, maximum directory depth.
- Refuse to follow a symlink that leaves the root, and terminate on a symlink
  loop.
- Produce a diagnostic for every file excluded by a budget, naming the limit.
- Extend the developer command to take a root directory as well as file paths.

DoD:

- Tests build a temporary tree and assert the discovered set, including that an
  excluded directory contributes nothing and that a file of an unmapped
  extension is not a unit.
- A file over the size budget appears as a diagnostic, not as a silent omission.
- A symlink loop terminates and is reported.
- `zig build test-core` still passes with no filesystem dependency in `src/core/`.

### Stage 2: Unit Identity Independent Of Path

Purpose: make a rename survivable before anything has to survive one.

Tasks:

- Give source units allocated identity and tombstones, so a removed unit's id is
  never reused.
- Move path and language to unit properties refreshed like evidence.
- Change `IdentityEvidence.scope` to carry the unit's identity rather than its
  path, and update both frontends to supply it.
- Keep a path-based lookup available to consumers as a query over the unit's
  current property.

DoD:

- A unit-level test changes a unit's path and asserts that every entity in it
  keeps its id and its assertions.
- A test asserts that two units with the same path in different roots are
  distinct units, and that identity evidence equality does not make two entities
  in different units correspond.
- Existing slice tests pass unchanged in meaning; any test that asserted a path
  as a scope is updated to assert the property instead.

### Stage 3: Scan Reconciliation

Purpose: turn a rescan into decisions about units, using the vocabulary entity
reconciliation already uses.

Tasks:

- Compare a new scan against the registry: unchanged, changed, added, removed,
  and renamed with identical content.
- Preserve unit identity where correspondence is established; record `lost` where
  a unit was replaced without it; record `removed` where nothing replaced it.
- Remove the entities of a removed unit and withdraw its assertions, recording
  entity identity events for each.
- Count frontend invocations, and reanalyze only changed, added, and renamed
  units whose contents differ.
- Record unit identity events in the graph beside entity identity events.

DoD:

- Rescanning an unchanged tree invokes no frontend and produces no identity
  event.
- Renaming a file with identical content preserves the unit id and every entity
  id inside it, and records `preserved`.
- Renaming a file while changing it records `lost` for the old unit and
  `created` for the new one, and the break is visible as a break.
- Deleting a file removes its entities with recorded events and leaves other
  units untouched.
- A test asserts the frontend invocation count directly, so "only the affected
  region" is measured rather than inferred.

### Stage 4: Affected-Region Proof At Scale

Purpose: make the incrementality claim falsifiable on a tree large enough for it
to be false.

Tasks:

- Add `fixtures/repository-scale/` with a generated multi-unit tree in both
  fixture languages, and rescan histories over it.
- Assert that an edit to one unit reanalyzes one unit, whatever the tree size.
- Assert that adding unrelated units does not reanalyze existing ones.
- Add a guard against accidental quadratic behavior on the ingestion path: assert
  that the work a rescan does is proportional to what changed, not to the graph,
  for the operations this plan introduces.
- Record the observed cost of `publish` over the fixture tree in the progress
  log as a measured number, without changing the design.

DoD:

- Tests over a tree of at least a few dozen units demonstrate the two assertions
  above with explicit counts.
- The quadratic guard fails if a lookup that should be keyed becomes a scan.
- The progress log records the measured `publish` cost and names it as an
  accepted risk rather than a solved problem.

### Stage 5: Cross-Unit Dependency Tracking

Purpose: give invalidation something real to act on, without inventing import
semantics.

This stage opens with a decision, because its second half touches
[§1](../../ARCHITECTURE_CONSTITUTION.md#1-semantic-graph-is-the-product).

Tasks:

- Implement `core/dependencies`: a frontend batch may declare that its result
  depended on facts about units other than its own, and a change to those units
  marks the dependent unit for reanalysis. Prove it with a synthetic declared
  dependency, with no language semantics involved.
- Write an ADR answering whether recording a repository-wide unique-name match as
  an **approximate** assertion is compatible with §1 and §3, given that §1 forbids
  an approximate mechanism from establishing a program relationship while §3
  provides the approximate category and requires it to stay distinct from fact.
- If the ADR accepts it: record such matches as `approximate` assertions with
  their basis, make them depend on the set of repository-wide definitions of that
  name, and invalidate them when that set changes.
- If the ADR rejects it: stop at the dependency mechanism. The stage completes
  with the mechanism proven by the synthetic dependency and no cross-unit
  resolution, and the plan still completes.

DoD:

- The dependency mechanism is proven either way: declaring a dependency on
  another unit causes reanalysis when that unit changes, and no reanalysis when
  it does not.
- The ADR exists and is linked from `CORE.md`'s open questions or from
  `SPEC.md`, whichever its conclusion belongs to.
- If accepted: an approximate assertion is produced, counted, never presented as
  a fact, and invalidated when a second definition of the same name appears in
  another unit. `Snapshot.countApproximateAssertions` becomes non-zero for a
  fixture, which
  [CONFORMANCE.md](../../CONFORMANCE.md#required-scenario-families) asks for
  under Knowledge categories.
- If rejected: the progress log records the reasoning and the plan's completion
  definition is met without the second half.

### Stage 6: Closure And Documentation

Purpose: leave the repository consistent and the next decision ordered.

Tasks:

- Update `MEMORY.md` with the new ingestion reality, the new boundaries, and the
  replaced residual risk.
- Update `SPEC.md`'s source identity and invalidation rows to what is now
  settled, and leave what is not.
- Update `CONFORMANCE.md`'s current status with the scenario families this work
  supplies evidence for.
- Update `GLOSSARY.md` if this work introduced vocabulary, as `freshness` and
  `stale` were introduced before.
- Update the progress log with every stage outcome, exact commands, skipped
  checks, review findings, and residual risk.
- Record, explicitly, what `module` and `IMPORTS` now have that they did not, and
  what they still lack.

DoD:

- `zig build test-core`, `zig build test-core -Dgrammars-dir=/nonexistent`, and
  `zig build test` pass.
- `zig fmt --check build.zig src tests` is clean and
  `./scripts/check-agent-attribution.sh --all` passes.
- The developer command indexes this repository's own `fixtures/` tree by root
  and reports per-unit analysis state.
- No document claims published coverage, an admitted `module` or `IMPORTS`, or a
  semantic contract version.
- Working tree is clean after the final commit.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Discovery finds the right units | Silent omission looks like an empty repository | Focused integration | Temporary tree with included, excluded, and unmapped files | Excluded directory, unmapped extension, oversized file, symlink loop | Stage 1 tests and diagnostics |
| Core stays free of the filesystem | Environment creeps into the shared model | Runtime smoke | `zig build test-core -Dgrammars-dir=/nonexistent` | An `std.Io` import appearing under `src/core/` | Stage 1 and Stage 6 commands |
| Unit identity survives a rename | Renaming a file destroys every identity inside it | Unit plus fixture/golden | Path changed, ids compared | Rename with content change; two roots with the same relative path | Stage 2 and Stage 3 tests |
| Identity loss stays visible | A replaced unit looks like unrelated deletion and creation | Fixture/golden | Unit identity events beside entity identity events | Renamed-and-edited file; deleted file | Stage 3 tests |
| Only the affected region is reanalyzed | Every edit quietly rebuilds the repository | Fixture/golden with counters | Frontend invocation count on a multi-unit tree | Unchanged rescan; unrelated growth | Stage 3 and Stage 4 counts |
| Ingestion does not go quadratic | Repository scale becomes pathological by accident | Focused integration | Work proportional to change, not to graph size | A keyed lookup replaced by a scan | Stage 4 guard |
| Invalidation acts on something real | An invalidation rule exists that never runs | Focused integration | Synthetic declared cross-unit dependency | Dependency target unchanged; dependency target changed | Stage 5 tests |
| Approximate stays distinct from fact | A name match is presented as a resolved reference | Unit plus fixture/golden | Assertion category and query filters | Second same-named definition appears; only match disappears | Stage 5 tests, if the ADR accepts |
| Freshness still holds at scale | A unit goes stale and its claims answer as current | Fixture/golden | Per-unit analysis state over many units | Rescan where one unit fails to parse | Stage 3 and Stage 4 tests |
| Local operation and privacy | Ingestion reads outside the declared root | Runtime smoke | Walk confined to the root | Symlink pointing outside the root | Stage 1 tests |
| Documentation stays truthful | Cross-unit work reads as `IMPORTS` having been admitted | Documentation review | Explicit statement of what is still blocked | Wording that implies module semantics | Stage 6 diff review |

## Plan Readiness Gate

This plan is ready for implementation when:

- the executor starts from a clean or explicitly coordinated working tree;
- `RULES.md`, `ARCHITECTURE_CONSTITUTION.md`, `SPEC.md`, `CORE.md`,
  `CONFORMANCE.md`, `MEMORY.md`, ADR 001, ADR 002, reports 001 to 004, and this
  plan have been read;
- the executor records progress in
  [docs/reports/005_repository_scale_ingestion_progress.md](../reports/005_repository_scale_ingestion_progress.md);
- Stage 2 is not started before Stage 1 has landed discovery, because changing
  identity under a hand-written unit list proves nothing.

Known execution stop conditions:

- Stop if a stage appears to require admitting `module`, `IMPORTS`, or any new
  core kind. That is a requirements change with its own lifecycle.
- Stop if Stage 5's ADR cannot be answered without reinterpreting a
  constitutional clause. §18 admits no exception; a clause that cannot be
  followed as written is grounds for a fork, not for a generous reading.
- Stop if unit identity cannot be made path-independent without changing an
  accepted core definition in `CORE.md`.
- Stop if the work requires persistence or a public contract to pass its tests;
  that means the plan has grown beyond its scope.

## Completion Definition

The plan is complete when the graph can be built and maintained over a discovered
repository, a rename preserves the identity of everything inside the renamed
unit, an edit demonstrably reanalyzes only the affected region on a tree large
enough for that to be falsifiable, invalidation acts on a real recorded
dependency, and the progress log records stage outcomes, verification evidence,
skipped checks, residual risk, and what `module` and `IMPORTS` still lack.
