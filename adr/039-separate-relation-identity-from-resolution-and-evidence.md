---
file_type: adr
decision_id: ADR-039
title: Separate Relation Identity From Resolution And Evidence
status: accepted
date: 2026-08-02
deciders:
  - project owner
tags:
  - architecture
  - semantic-core
  - relations
  - identity
summary: A typed relation's semantic identity derives only from relation type, source endpoint, semantic target key, and flow payload; mutable resolution and evidence fields are excluded from relation_id, and invalid facts are rejected through an explicit internal schema with structured diagnostics instead of silent filtering.
agent_summary: Read this ADR before adding relation-backed consumers or changing relation_id. relation_id must be a pure function of stable semantic fields (relation type, source unit, target key, local_name/arg_index) scoped by schema version. Never fold target_unit_ids, resolution_status, evidence_quality, provenance, or evidence_location into identity. Validate relations through the explicit schema and surface invalid facts as diagnostics, not silent drops.
supersedes: []
superseded_by: null
links:
  - adr/034-land-dataflow-facts-as-typed-relations-first.md
  - adr/037-scope-interprocedural-dataflow-v1.md
  - adr/038-make-typed-relations-the-canonical-semantic-graph.md
  - plans/013_open_gaps_closure_program.md
  - reports/014_open_gaps_closure_program_progress_log.md
---

# ADR-039: Separate Relation Identity From Resolution And Evidence

**Status**: Accepted
**Date**: 2026-08-02
**Deciders**: project owner

## Context

ADR-034, ADR-037, and ADR-038 established typed relations as the canonical
graph for new interprocedural dataflow facts. The v1 substrate in
`semidx.runtime.relations` computed `relation_id` from an input map that
included mutable resolution and evidence fields: `target_unit_ids`,
`resolution_status`, `evidence_quality`, `provenance`, and `evidence_location`.

The 2026-08-01 Stage 3 architecture re-review flagged two blocking problems
before relation-backed consumers land:

- **Identity is entangled with mutable state (High).** Because resolution and
  evidence participate in `relation_id`, an unresolved fact that later resolves,
  or a fact that gains richer evidence (for example additional SCIP or compiler
  input), produces a different `relation_id`. The same semantic edge would be
  replaced or duplicated instead of enriched, breaking stable identity across
  snapshots and across evidence providers.
- **Validation is permissive and silent (Medium).** `valid-relation?` checked
  only basic field presence, and `normalize-relations` filtered invalid facts
  with no diagnostics, so malformed relations disappeared without a signal.

Both must be fixed before the bounded traversal kernel and any
retrieval/impact projections consume relations.

## Decision Drivers

- One semantic edge must keep one identity as it moves from unresolved to
  resolved and as evidence accumulates.
- Multiple evidence providers over the same edge must enrich a single relation,
  not mint parallel ones.
- Invalid facts must be observable, not silently dropped.
- Identity and validation must stay storage-independent and deterministic.

## Considered Options

1. Keep resolution/evidence in `relation_id` and deduplicate downstream.
2. Derive `relation_id` only from stable semantic fields, and add an explicit
   validation schema that surfaces invalid facts as structured diagnostics.
3. Introduce a separate immutable identity record alongside the mutable fact.

## Decision

We accept option 2.

### Identity

A relation's semantic identity derives only from stable semantic fields:

- `relation_type`
- `source_unit_id` (source endpoint)
- `target_key` (semantic target key)
- flow payload: `local_name` and `arg_index`

scoped by `relation_schema_version`. `relation-id-input` selects only these
fields. Mutable resolution and evidence fields — `target_unit_ids`,
`resolution_status`, `evidence_quality`, `provenance`, `evidence_location` — are
excluded from `relation_id`. Resolving a fact or attaching richer evidence
therefore enriches one relation instead of creating a second semantic edge.

### Validation and diagnostics

`relation-errors` is the explicit internal schema. It returns a vector of
structured error maps (`{:code :field :message}`); an empty vector means valid.
It rejects:

- non-map relations, missing `relation_id`, missing `source_unit_id`;
- unknown `relation_type` (must be in `relation-types`);
- unknown `resolution_status` (must be in `resolution-statuses`);
- unknown `evidence_quality` (must be in `evidence-qualities`);
- `relation_schema_version` mismatch;
- resolved relations without at least one `target_unit_id`
  (resolved requires resolved targets);
- non-map `evidence_location` or `provenance` when present.

Ambiguous and unresolved relations remain conservative and are accepted without
requiring targets. `valid-relation?` is defined as an empty `relation-errors`.
`normalize-relations-with-diagnostics` partitions normalized facts into valid
relations and diagnostics for invalid facts; `index-relations` surfaces those as
`:relation_diagnostics` on the snapshot instead of dropping them silently.

## Consequences

### Positive

- A semantic edge keeps one `relation_id` across resolution transitions and
  across evidence providers, enabling later enrichment rather than replacement.
- Invalid facts are observable through snapshot `:relation_diagnostics`.
- Identity and validation stay pure, deterministic, and storage-independent.

### Negative

- Adding a new relation kind now requires registering it in `relation-types`
  before producers emit it.
- Adding a stable identity dimension (a new flow-payload field) is a deliberate
  identity change that must be recorded, since it alters `relation_id`.

## References

- ADR-034: typed relations first for new dataflow facts
- ADR-037: bounded interprocedural dataflow v1 scope
- ADR-038: typed relations as the canonical semantic graph
- `plans/013_open_gaps_closure_program.md`
- `reports/014_open_gaps_closure_program_progress_log.md`
