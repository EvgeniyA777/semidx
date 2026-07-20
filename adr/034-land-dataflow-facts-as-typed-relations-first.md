---
file_type: adr
decision_id: ADR-034
title: Land Dataflow Facts As Typed Relations First
status: accepted
date: 2026-07-19
deciders:
  - project owner
tags:
  - architecture
  - semantic-core
  - relations
summary: New interprocedural/dataflow facts from the 013 Stage 3 semantic tranche land directly in the typed-relation model from plan 007, as its first consumer; migration of existing calls/imports edges to that model is explicitly deferred.
agent_summary: Read this ADR before starting plans/013 Stage 3 or any typed-relation work from plans/007 Stage 4. The decision of record is the hybrid path - new dataflow facts use the typed-relation schema from day one, while existing calls/imports edges stay untouched until a later, separately gated migration.
supersedes: []
superseded_by: null
links:
  - plans/013_open_gaps_closure_program.md
  - plans/007_semidx_extension_architecture_resolution_plan.md
  - reports/016_architecture_assessment_open_plans_and_ideas.md
---

# ADR-034: Land Dataflow Facts As Typed Relations First

**Status**: Accepted  
**Date**: 2026-07-19  
**Deciders**: project owner

---

## Context

Two active plans describe overlapping edge models with different migration
disciplines:

- `plans/013` Stage 3 plans the interprocedural / dataflow-sensitive
  resolution v1 tranche by "extending `semantic_ir.clj` with the
  interprocedural edge/flow representation" - i.e. new edge kinds inside the
  existing Semantic IR, next to `calls` and `imports`.
- `plans/007` Decision 11 / Stage 4 defines a general typed-relation model
  (`relation_type`, `resolution_status`, `evidence_quality`, `provenance`,
  `evidence_location`) introduced additively, with dual-write from existing
  calls/imports and shadow-mode parity gates before any consumer switches.

Left unresolved, the implementing agent of Stage 3 would have to choose an
edge model silently - which repository rules forbid for conflicting current
documents. Choosing the 013 path wholesale creates a second ad-hoc edge
vocabulary that later has to migrate into relations anyway; choosing the 007
path wholesale front-loads the full dual-write and parity apparatus before any
semantic value ships.

`reports/016` section 4 records this fork; this ADR resolves it.

## Decision Drivers

- Ship semantic value (dataflow-aware resolution) without months of
  migration infrastructure first.
- Avoid creating new edge kinds that are born legacy - every new fact should
  land in the model the architecture has already committed to.
- Protect existing graph consumers (callers/callees indexes,
  `resolve_context` authority selection, `impact_analysis`, `snapshot_diff`):
  their inputs must not change semantics without parity evidence.
- Keep confidence honest: new facts must not inflate confidence merely by
  existing (`plans/007` Decision 12 discipline).
- Preserve the option to migrate `calls`/`imports` later on a schema proven by
  real usage.

## Considered Options

### Option 1. Extend the existing Semantic IR directly

Add interprocedural/dataflow edges as new keys beside `calls`/`imports` in the
current IR (the literal reading of `plans/013` Stage 3).

### Option 2. Full typed-relation rollout first

Execute `plans/007` Stage 4 completely - relation schema, dual-write of
existing calls/imports, shadow projections, golden-parity gates - and only
then build dataflow facts on top.

### Option 3. Hybrid: new facts as typed relations, old edges deferred

Introduce the typed-relation schema and indexes now, but with exactly one
producer: the new interprocedural/dataflow facts from Stage 3. Existing
`calls`/`imports` extraction, storage, and every current consumer stay
untouched. The dual-write + parity migration of old edges remains a separate,
later stage.

## Decision

We accept Option 3: the hybrid.

- The typed-relation schema from `plans/007` Decision 11 is implemented as
  part of the Stage 3 tranche: `relation_id`, `source_unit_id`, `target_key`,
  `target_unit_ids`, `relation_type`, `resolution_status`, `evidence_quality`,
  `provenance`, `evidence_location`, plus forward/reverse relation indexes.
- All new interprocedural/dataflow facts (parameter-to-call binding,
  local-variable call-target propagation, return-value threading - final v1
  scope to be fixed in the Stage 3 ADR) are emitted **only** as typed
  relations. No new ad-hoc keys are added to the existing IR edge set.
- Existing `calls`/`imports` facts, their storage projections, and all current
  consumers are **not** dual-written and **not** migrated in this step.
  Because the new relations have no pre-existing consumers, no golden-parity
  gate is required for them; conservative-resolution discipline (no
  over-linking, ambiguous flows stay unresolved) and the confidence
  non-inflation rule still apply in full.
- Retrieval and impact surfaces consume the new facts through explicit
  projections over the relation indexes, never by reaching into
  producer-specific structures - keeping the dependency direction from
  `plans/007` intact.
- The later migration of `calls`/`imports` into relations, when scheduled,
  follows the original `plans/007` Stage 4 discipline unchanged (dual-write,
  shadow projections, golden parity, per-consumer switch), now against a
  schema hardened by real Stage 3 usage.

Option 1 loses because it creates a second edge vocabulary that contradicts an
accepted architecture plan and guarantees a future migration of brand-new
code. Option 2 loses because it spends the highest-risk engineering budget
(parity-gated migration of load-bearing edges) before any new semantic value
exists, and freezes the relation schema before a single real producer has
exercised it.

## Consequences

### Positive

- Stage 3 can start without waiting on migration infrastructure; the parity
  apparatus is deferred to where it is actually needed.
- The relation schema gets validated by a real, low-risk producer before the
  expensive calls/imports migration commits to it.
- No silent behavior change surface: existing consumers keep reading exactly
  the edges they read today.

### Negative

- Two edge representations coexist for an extended period (legacy
  calls/imports plus typed relations); graph-consuming code must be explicit
  about which it reads.
- Schema changes discovered during Stage 3 require relation-index migration
  even before old edges move in - versioning of the relation schema must be
  additive from day one.
- The full unification promised by `plans/007` Stage 4 is intentionally
  postponed; anyone reading 007 alone will see an unexecuted stage and must
  follow the link here for the current sequencing.

### Follow-Up

- The Stage 3 scoping ADR (numbered at execution time, per `plans/013`) must
  fix the v1 dataflow scope and lane order **within** this relation-first
  constraint.
- When Stage 3 lands, update `plans/007` Stage 4 wording (or its successor
  plan) to reference this ADR and the already-existing relation schema.
- Add the corresponding line to `MEMORY.md` with the Stage 3 implementation
  commit (deferred from this ADR's commit to avoid colliding with the
  in-flight Stage 1 working tree).

## Status Changes

None. This ADR narrows the execution order of `plans/007` Stage 4 and
`plans/013` Stage 3 without superseding either plan.

## References

- `plans/007_semidx_extension_architecture_resolution_plan.md` - Decisions 11
  and 12, Stage 4
- `plans/013_open_gaps_closure_program.md` - Stage 3
- `reports/016_architecture_assessment_open_plans_and_ideas.md` - section 4
  (the recorded fork)

## Definition Of Done

Stage 3 ships its interprocedural/dataflow facts exclusively through the typed
relation schema and indexes; no new edge keys appear in the legacy IR edge
set; existing callers/callees, `resolve_context`, `impact_analysis`, and
`snapshot_diff` behavior for protected cases is unchanged; the deferred
calls/imports migration remains documented as a future stage governed by
`plans/007` Stage 4 gates.
