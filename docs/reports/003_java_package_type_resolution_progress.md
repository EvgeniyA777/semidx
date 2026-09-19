---
title: "Java package type resolution progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-14"
---

# 003: Java Package Type Resolution Progress

Companion log for
[docs/plans/003_java_package_type_resolution.md](../plans/003_java_package_type_resolution.md).

## Current Status

Plan 003 is complete. Stages 1 to 4 are implemented, Stage 5 synchronized the
documentation, and the final findings-first review found no confirmed defects.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) and [plan 003](../plans/003_java_package_type_resolution.md). Applied the Plan Readiness Gate; result: ready for execution. |
| Stage 1: Context and external target contract | Completed | `DraftTarget.external` names a graph-established definition together with its provider unit. Integration checks every external target before touching the graph. A stale claim may outlive a withdrawn cross-unit target; a current one may not. |
| Stage 2: Java package binding context | Completed | The analyzer builds a per-package binding table from current Java class facts and hands it to the Java frontend; duplicate names arrive as ambiguous. The frontend does not use it yet. |
| Stage 3: Java cross-unit type resolution | Completed | A simple type name in an explicit package resolves to the one current top-level class another unit declares in that package, as a `REFERENCES` fact with a dependency on the provider. Every other case stays unresolved with its reason. The repository-scale fixture expectation moved to Stage 4 (see below). |
| Stage 4: Package export invalidation | Completed | Every index mutation (scan, add, edit, remove) reanalyzes dependents of changed providers and the other Java units of every package whose exported classes changed, ordered so a unit read before the last change is read again. The repository-scale `Helper` reference is now a fact. |
| Stage 5: Documentation, review, and closure | Completed | `MEMORY.md`, `SPEC.md`, and `CONFORMANCE.md` synchronized; closure commands pass; final review recorded below with no confirmed defects. |

## Plan Readiness Gate

Applied on 2026-09-14. The detailed gate record lives in
[plan 003](../plans/003_java_package_type_resolution.md#plan-readiness-gate).
Re-checked by the implementing agent before Stage 1; no hard fail.

Result: ready for execution.

## Stage 1: Context And External Target Contract

Changed files: `src/core/contract.zig`, `src/core/graph.zig`,
`src/core/reconcile.zig`.

Decisions taken inside the plan's boundary:

- `contract.ExternalTarget` carries `entity` and `provider`. The frontend
  cannot discover either by itself; the analyzer hands them over.
- `reconcile.integrate` validates external targets before it opens a revision,
  so a rejected batch leaves the unit as its previous analysis left it. The
  checks, each with its own error: only `REFERENCES` and `CALLS` may be external
  (`CONTAINS` and `DEFINES` describe one unit's own organization); the provider
  is not the analyzed unit; the batch declares a dependency on the provider; the
  target exists, is live, is a `definition`, was introduced by that provider,
  and `Graph.currentDefinitionFact` finds its existence recorded as a current
  fact of a currently analyzed provider.
- `Graph.currentDefinitionFact` reads only the provider unit's assertion
  bucket and counts that into `unit_work`.
- `Graph.checkInvariants` still refuses a current relationship whose target
  entity is gone. It now tolerates the one honest exception cross-unit claims
  introduce: a stale claim (recorded before its own unit's contents last
  changed) whose target another unit later withdrew. Without this, a dependent
  edited into unparsable source would make every later publish fail once its
  provider removed the target, because the dependent cannot be analyzed again.
- The analyzer-side context path planned for this stage moved to Stage 2, where
  its first real content (the Java package binding table) is defined. Stage 1
  stayed in the shared core.

Verification:

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 84/84 passed (4 new reconcile tests). |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 84/84 passed. |
| `zig build test --summary all` | 127/127 passed; vertical-slice tests unchanged. |
| `zig fmt build.zig src tests` | Applied; no further changes. |

## Stage 2: Java Package Binding Context

Changed files: `src/frontends/java.zig`, `src/frontends/java_packages.zig`
(new), `src/frontends/root.zig`.

Decisions taken inside the plan's boundary:

- `java.Context` is the analyzer context path the plan asked for. It holds one
  package and its `TypeBinding`s (`unique` external target or `ambiguous`
  count). `Context.empty` is what a unit analyzed without a graph receives;
  `Analyzer.analyze` takes an optional graph for that reason. Clojure receives
  no context.
- `java_packages.exportsOf` is the single definition of a Java package export:
  a live `definition` with Java language, role `class`, no container, a
  non-empty `java.package` label, whose existence `Graph.currentDefinitionFact`
  finds recorded as a current fact by `frontend.java`. A stale or failed unit
  exports nothing.
- `java_packages.Packages` keeps one piece of state between analyses: which
  units have declared classes in which package. It is a hint that bounds the
  table to one package; every hinted unit is read back from the graph through
  `exportsOf`, so a unit that moved package or went stale contributes nothing.
  No shared-core query was added for packages, and no package entity exists.
- `java.declaredPackage` rebuilds the package name from its identifiers and
  skips annotations. The previous `packageName` took the first named child, so
  an annotated package declaration would have produced an annotation's text as
  the package. The `java.package` label now uses the same function.
- The analyzed unit's own previous classes are excluded from its context; its
  local classes are resolved from its own batch.

Verification:

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 131/131 passed (4 new frontend tests). |

## Stage 3: Java Cross-Unit Type Resolution

Changed files: `src/frontends/java.zig`, `tests/vertical_slice_test.zig`.

Decisions taken inside the plan's boundary:

- Resolution order for a field type or method return type: a class declared in
  the unit stays a local fact, exactly as before. Otherwise the name must be a
  `type_identifier` in a unit with an explicit package, and the frontend must
  rule out every Java scope that takes precedence over a same-package type
  (JLS 6.4.1): a type parameter of the enclosing method or class, a member type
  declared in the enclosing class, a member type the class may inherit (any
  `extends` or `implements` clause), a single-type or single static import of
  that simple name, and a top-level interface, enum, record, or annotation type
  of that name in the unit. Wildcard imports and `java.lang` rank below the
  package and do not block. If one of these cannot be ruled out, the reference
  stays unresolved with an explanation naming it. This is the plan's stop
  condition applied: without these checks the producer could not distinguish
  scoping from a string match.
- A unique binding becomes a `DraftTarget.external` fact; an ambiguous one is
  unresolved and names the count; a missing one is unresolved and names the
  package, which covers both "declared nowhere" and "declared in another
  package" without looking at other packages.
- One dependency is declared per provider unit, however many references read
  it. Unresolved names declare nothing; Stage 4's package invalidation is what
  keeps them current.
- The Java capabilities `coverage_note` states the new rule and its exclusions.

Deviation from the plan's Stage 3 DoD: the repository-scale Java `Helper`
expectation could not flip in this stage. Discovery analyzes
`java/demo/Greeter.java` before `java/demo/Helper.java`, so at the time
`Greeter` is read no `Helper` fact exists; only Stage 4's package-export
invalidation reanalyzes it. The fixture test is therefore updated in Stage 4.
Stage 3's own acceptance is proved with units added provider-first.

Verification:

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 134/134 passed (3 new integration tests); the repository-scale test still passes with its pre-Stage-4 expectation, confirming the ordering analysis above. |

## Stage 4: Package Export Invalidation

Changed files: `src/root.zig`, `src/core/dependencies.zig` (module comment),
`tests/vertical_slice_test.zig`, `fixtures/repository-scale/README.md`.

Decisions taken inside the plan's boundary:

- `Index.Upkeep` replaces `Index.propagateInvalidation` and runs for every
  mutation: `applyScan`, and now also `addUnit`, `applyEdit`, and `removeUnit`.
  Leaving the direct calls without it would let a provider edit remove a class a
  current dependent still names, and the next publish would refuse the graph.
- Dependency propagation is computed before the batch touches anything. The
  previous implementation computed it after removals, and
  `Graph.removeSourceUnit` forgets every declaration naming the removed unit, so
  a removed provider's dependents were never reached. That defect was latent
  while no producer declared dependencies; its old doc comment already claimed
  the pre-scan reading this now implements.
- Package export change: each removal and own-content analysis compares the
  unit's `java_packages.exportsOf` before and after, and records the step at
  which each package's exports last changed. At the end, a hinted unit of that
  package is reanalyzed when it currently exports into the package and was not
  analyzed at or after that step. This is what makes a unit read early in a scan
  (the repository-scale `Greeter`, read before `Helper`) current, without
  reanalyzing units that already saw the final bindings.
- A unit that is stale or cannot be analyzed exports nothing and is not owed a
  package reanalysis, since reading its unchanged contents again would fail the
  same way. It can still be reached through its dependency declaration; its
  stale claim then survives under Stage 1's invariant rule.
- Reanalysis never changes exports, because exports depend only on a unit's own
  contents, so one round settles a batch. Owed units are sorted by id so the
  order does not follow hash-map iteration.
- Work stays package-scoped: an export change in `demo` reads `demo`'s other
  units only, and a body edit that leaves exports unchanged reads only the units
  that declared a dependency on the provider.

Verification:

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 140/140 passed (6 new integration tests; repository-scale test updated to expect the `Helper` fact, `invalidated == 2`, `analyzed == 8`). |
| Mutation: package-change marking disabled | 7 tests failed, including the repository-scale, provider-addition, provider-lifecycle, invocation-count, stale-dependent, and direct-edit tests. Restored. |
| Mutation: dependency-propagated reanalysis disabled | `a provider body edit reaches its dependent through the dependency alone` failed. Restored. |
| `zig build run -- fixtures/repository-scale` | Observational: `Helper` no longer listed among unresolved targets; `decorate` still is; 0 approximate, 0 stale. |

## Stage 5: Documentation, Review, And Closure

Changed files: `MEMORY.md`, `SPEC.md`, `CONFORMANCE.md`, this log.

- `MEMORY.md` records the Java same-package producer, the external-target
  contract, both invalidation mechanisms and their wiring into every `Index`
  mutation, the stale-claim invariant, the narrowed "does not exist" list, the
  new load-bearing limitations, and near-term priorities past this workstream.
- `SPEC.md` records the producer as implementation guidance for one Java rule
  and updates the Invalidation row.
- `CONFORMANCE.md` records the cross-unit evidence per scenario family without
  adopting any family as a gate.
- `CORE.md` is unchanged. No kind's meaning or admission status changed: the
  cross-unit reference is an accepted `REFERENCES` between accepted
  `definition`s, and `module` / `IMPORTS` remain blocked. The evidence that a
  Java package fit in extension vocabulary is noted in `MEMORY.md` for a future
  admission review rather than written into admission text now.
- Historical records (reports 001 and 002, plan 002, ADR 003) still say that no
  cross-unit assertions exist. They describe their own time and were not
  rewritten.

Closure verification:

| Command | Result |
| --- | --- |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 84/84 passed. |
| `zig build test-core --summary all` | 84/84 passed. |
| `zig build test --summary all` | 140/140 passed. |
| `zig fmt --check build.zig src tests` | Passed. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |
| `git diff --check` | Passed. |
| `./scripts/check-memory-freshness.sh` | Passed. |
| `zig build run -- fixtures/repository-scale` | Observational only; see Stage 4. |
| `semidx-code-review` findings-first review | Completed; no confirmed findings. |

## Review

Final findings-first review completed on 2026-09-14 over the five implementation
commits from `926a8f1` through `fa7a4a0`, against
[ADR 004](../adr/004_allow_java_same_package_type_resolution.md) and
[plan 003](../plans/003_java_package_type_resolution.md).

Semantic Code Indexing was required by repository policy, but no callable
`create_index` tool was exposed through tool discovery in the reviewing
environment. The review therefore used targeted direct inspection of the final
diff and the changed files named in this log.

Findings:

| Severity | Classification | Finding | Disposition |
| --- | --- | --- | --- |
| — | Review result | No confirmed defects in semantic identity, provenance and resolution, incremental maintenance, frontend coverage boundaries, runtime behavior, documentation synchronization, or test coverage. | Closed. |

Notes reviewed but not filed as defects:

- `Index.renameUnit` remains a path-only operation. Java package membership is
  read from source text, not from paths, so a path rename does not change package
  exports and does not owe package upkeep.
- The Java type-parameter and supertype checks are intentionally conservative:
  they may leave real references unresolved, but they do not create false facts.
  This is recorded as residual risk.
- `java_packages.Packages` keeps stale hints until analyzer release, but every
  hint is re-read from graph state before use. This is recorded as residual
  risk.

Reviewer verification:

| Command | Result |
| --- | --- |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 84/84 passed. |
| `zig build test-core --summary all` | 84/84 passed. |
| `zig build test --summary all` | 140/140 passed. |
| `zig fmt --check build.zig src tests` | Passed. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |
| `./scripts/check-memory-freshness.sh` | Passed. |
| `git diff --check` | Passed. |
| `zig build run -- fixtures/repository-scale` | Observational: `Helper` is no longer unresolved; `decorate` still is; 0 approximate assertions; 0 stale assertions. |

## Residual Risk

- **The repository is treated as one Java classpath.** Two build modules that
  share a package name but cannot see each other are one package to this rule:
  a class in one can be resolved to a class in the other, as a fact. Duplicates
  across them are reported as ambiguity, which is safe; a single provider is not.
  Multi-module boundaries need their own requirement.
- **Conservative shadowing leaves real references unresolved.** Any class with
  an `extends` or `implements` clause resolves no cross-unit type names, because
  inherited member types are not analyzed. Interfaces, enums, records, and
  nested classes are never providers.
- **Same-unit resolution is unchanged and still ignores shadowing.** A class
  declared in the unit wins over a type parameter of the same name, as it did
  before this plan; the new shadowing checks apply only to cross-unit
  resolution.
- **Invalidation is coarse.** A provider body edit rereads every dependent, and
  an export change rereads every other unit of its package. On a first scan each
  explicit package is read about twice, and building one package's table costs
  that package's size per analysis, so a very large single package is quadratic
  to build.
- **Freshness is still per unit.** A dependent's claim is not marked stale by
  its provider's state; `Index` keeps such a claim from being observed by
  reanalyzing the dependent in the same batch. Code that mutates `Graph` or calls
  `Analyzer.indexUnit` directly bypasses that upkeep, and `publish` then refuses
  a current claim naming a withdrawn entity rather than serving it.
- **A stale claim can name an entity that left the graph.** Consumers asking for
  stale relationships can receive a target id absent from the snapshot's
  entities; the target's identity event records its removal.
- **The package hint is bound to one graph and never pruned.** An `Analyzer`
  reused across graphs mixes hints (harmless, since every hint is re-read, but
  wasted work), and hints for units that left a package stay until the analyzer
  is released.
- **Declarations recorded during a batch are not propagated within it.** A unit
  analyzed early in a scan can resolve to a provider whose body changes later in
  the same scan and is not reread for it. That is safe today because the class
  keeps its identity when its exports do not change, and an export change is
  caught by package invalidation; a finer dependency rule would have to revisit
  it.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Frontends never allocate or invent identity | An external id is taken on trust | Unit (reconcile) | Validation before mutation | Unknown id, file entity, wrong provider, undeclared provider, stale provider, removed target, structural kind | `an external target is refused unless it is a current definition of its declared provider` |
| External targets integrate as facts | Valid target dropped or duplicated | Unit (reconcile) | Snapshot query by target id | — | `a batch can target a definition another unit established` |
| Publication never hands out a dangling current fact | Provider removal breaks publish or leaks | Unit (reconcile/graph) | `checkInvariants` | Stale claim tolerated; current claim refused | `only a stale claim may outlive ...`, `a current claim naming a withdrawn definition is refused at publication` |
| Package context is language scoping, not name matching | Other package, default package, or stale class offered as a candidate | Integration (analyzer + parser) | `Analyzer.javaContext` | Other package, default package, nested package, self, stale provider, annotated package | `a java context leaves out other packages, ...` |
| Ambiguity is never resolved silently | One duplicate picked | Integration | `Packages.context` | Two providers of one name | `a class name declared twice in a package reaches the context as ambiguous` |
| Same-package names become facts only under ADR 004 | Name matching sneaks back in | Integration (Index) | `java.resolveType` | Qualified, other package, missing, default package, ambiguous, class and method type parameter, member type, supertypes, import, non-class type | `java type names outside the same-package rule stay unresolved and say why` |
| Same-unit behavior preserved | Local class displaced by a package binding | Integration | `java.resolveType` | Same name in unit and package | `a type declared in the unit still resolves locally ...` |
| Cross-unit fact attributable, dependency recorded, roster unchanged | Fact without dependency or with a new entity kind | Integration | Snapshot + `graph.dependencies` | — | `a java type name resolves to the one class its package declares in another unit` |
| Added provider leaves dependent unresolved | No declaration reaches a dependent that read nothing | Fixture + rescan | `Upkeep` package marking | Dependent never edited | `adding a same-package provider resolves a dependent nobody edited`, repository-scale test |
| Removed, renamed, duplicated, or moved provider leaves a stale fact current | Fact names a withdrawn or no-longer-unique class | Rescan | `Upkeep` | Rename, replacement, duplicate, removal, package move; stale queries checked | `renaming, replacing, duplicating, moving, and removing a provider keep the dependent current` |
| Cross-unit dependency never triggers | Provider body edit ignored | Rescan | Dependency propagation | Exports unchanged | `a provider body edit reaches its dependent through the dependency alone` |
| Package invalidation becomes repository-wide | Work grows with unrelated packages | Invocation counts at two sizes | `Upkeep.finish` | 4 vs 24 units in another package, default package, Clojure | `a package export change costs its own package, not the repository` |
| Stale dependent blocks publication | Dangling claim after provider removal | Rescan | `checkInvariants` | Dependent unparsable | `a stale dependent survives its provider's removal without blocking publication` |
| Non-scan mutations skip upkeep | Direct edit leaves dangling current fact | Integration | `Index.applyEdit`, `removeUnit`, `addUnit` | — | `direct edits and removals keep cross-unit facts current without a scan` |

## Verification History

Documentation-only planning checks run during plan creation:

| Command | Result |
| --- | --- |
| `git diff --check` | Passed. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |
| `./scripts/check-memory-freshness.sh` | Passed. |
| `zig build test-core --summary all` | 80/80 tests passed across the parser-independent lanes. |

## Next Handoff

Plan 003 is closed. Future work should start from the residual risks above,
especially build-module/classpath boundaries for Java package scope, or from a
new narrow language-correct producer such as Java single-type imports. Either
requires its own decision record and plan.

Semantic Code Indexing (semidx MCP) failed to connect in the implementing
session (connection timeout), so code was located by targeted direct reads.
