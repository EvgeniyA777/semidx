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

Stage 1 is complete. Stage 2 is next.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created [ADR 004](../adr/004_allow_java_same_package_type_resolution.md) and [plan 003](../plans/003_java_package_type_resolution.md). Applied the Plan Readiness Gate; result: ready for execution. |
| Stage 1: Context and external target contract | Completed | `DraftTarget.external` names a graph-established definition together with its provider unit. Integration checks every external target before touching the graph. A stale claim may outlive a withdrawn cross-unit target; a current one may not. |
| Stage 2: Java package binding context | Not started | Next. |
| Stage 3: Java cross-unit type resolution | Not started | Blocked by Stage 2. |
| Stage 4: Package export invalidation | Not started | Blocked by Stage 3. |
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

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Frontends never allocate or invent identity | An external id is taken on trust | Unit (reconcile) | Validation before mutation | Unknown id, file entity, wrong provider, undeclared provider, stale provider, removed target, structural kind | `an external target is refused unless it is a current definition of its declared provider` |
| External targets integrate as facts | Valid target dropped or duplicated | Unit (reconcile) | Snapshot query by target id | — | `a batch can target a definition another unit established` |
| Publication never hands out a dangling current fact | Provider removal breaks publish or leaks | Unit (reconcile/graph) | `checkInvariants` | Stale claim tolerated; current claim refused | `only a stale claim may outlive ...`, `a current claim naming a withdrawn definition is refused at publication` |

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
[Stage 2](../plans/003_java_package_type_resolution.md#stage-2-java-package-binding-context).
Semantic Code Indexing (semidx MCP) failed to connect in the implementing
session (connection timeout), so code was located by targeted direct reads.
