---
title: "Java package type resolution progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "continue_from_next_stage"
updated: "2026-09-14"
---

# 003: Java Package Type Resolution Progress

Companion log for
[docs/plans/003_java_package_type_resolution.md](../plans/003_java_package_type_resolution.md).

## Current Status

Stages 1 to 3 are complete. Stage 4 is next.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) and [plan 003](../plans/003_java_package_type_resolution.md). Applied the Plan Readiness Gate; result: ready for execution. |
| Stage 1: Context and external target contract | Completed | `DraftTarget.external` names a graph-established definition together with its provider unit. Integration checks every external target before touching the graph. A stale claim may outlive a withdrawn cross-unit target; a current one may not. |
| Stage 2: Java package binding context | Completed | The analyzer builds a per-package binding table from current Java class facts and hands it to the Java frontend; duplicate names arrive as ambiguous. The frontend does not use it yet. |
| Stage 3: Java cross-unit type resolution | Completed | A simple type name in an explicit package resolves to the one current top-level class another unit declares in that package, as a `REFERENCES` fact with a dependency on the provider. Every other case stays unresolved with its reason. The repository-scale fixture expectation moved to Stage 4 (see below). |
| Stage 4: Package export invalidation | Not started | Next. |
| Stage 5: Documentation, review, and closure | Not started | Closure stage after implementation. |

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

## Verification History

Documentation-only planning checks run during plan creation:

| Command | Result |
| --- | --- |
| `git diff --check` | Passed. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |
| `./scripts/check-memory-freshness.sh` | Passed. |
| `zig build test-core --summary all` | 80/80 tests passed across the parser-independent lanes. |

## Next Handoff

Continue with
[Stage 4](../plans/003_java_package_type_resolution.md#stage-4-package-export-invalidation).
Semantic Code Indexing (semidx MCP) failed to connect in the implementing
session (connection timeout), so code was located by targeted direct reads.
