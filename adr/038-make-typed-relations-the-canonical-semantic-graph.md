---
file_type: adr
decision_id: ADR-038
title: Make Typed Relations The Canonical Semantic Graph
status: accepted
date: 2026-08-01
deciders:
  - project owner
tags:
  - architecture
  - semantic-core
  - relations
  - providers
summary: Typed relation facts and their snapshot indexes are the canonical semantic graph; Semantic IR is an extraction and normalization intermediate, while legacy call and import projections remain until their parity-gated migration.
agent_summary: Read this ADR before adding graph semantics, providers, or traversal. Emit new facts through the typed relation boundary; do not add graph fields to Semantic IR or create provider-specific graphs. Existing calls and imports remain compatibility projections until a separately approved parity-gated migration.
supersedes: []
superseded_by: null
links:
  - adr/034-land-dataflow-facts-as-typed-relations-first.md
  - adr/037-scope-interprocedural-dataflow-v1.md
  - plans/007_semidx_extension_architecture_resolution_plan.md
  - plans/013_open_gaps_closure_program.md
---

# ADR-038: Make Typed Relations The Canonical Semantic Graph

**Status**: Accepted
**Date**: 2026-08-01
**Deciders**: project owner

## Context

ADR-034 and ADR-037 established typed relations for new interprocedural
dataflow facts. Some planning language still describes Semantic IR as the only
normalized semantic model, which can invite new graph facts to be embedded in
IR or represented in provider-specific structures. That would recreate the
parallel-graph problem that the earlier ADRs were intended to avoid.

The project needs one graph boundary that can accept code-lane, contract,
documentation, dependency-injection, and compiler-index evidence without
changing retrieval consumers for every new provider.

## Decision Drivers

- Keep graph semantics independent of parser and provider implementation.
- Preserve backward compatibility for existing call and import consumers.
- Make bounded traversal explainable and portable across in-memory and
  persistent storage implementations.
- Allow future SCIP, OpenAPI, Protobuf, and documentation providers to emit
  facts through one contract.

## Considered Options

1. Continue adding graph fields to Semantic IR and adapt each provider to them.
2. Maintain separate graphs per provider and merge them only in retrieval.
3. Make typed relation facts and their snapshot indexes the canonical graph,
   retaining legacy call/import projections during a parity-gated migration.

## Decision

We accept option 3.

Semantic IR is the normalized intermediate representation for extraction and
resolution inputs. Typed relation facts, normalized by
`semidx.runtime.relations` and indexed on a snapshot, are the canonical source
of truth for all new graph semantics.

New graph facts must include a relation type, explicit source and target
identity, resolution status, and provenance/evidence. Consumer-facing paths,
such as bounded `FLOWS_TO` traversal and impact hints, are derived projections
over relation indexes; they are not independently stored graphs.

Existing `calls`, `imports`, caller indexes, and callee indexes remain legacy
compatibility projections until a separately approved migration proves parity.
This ADR does not require their immediate dual-write or replacement.

## Consequences

### Positive

- New providers share one graph contract and one traversal boundary.
- Dataflow and future cross-language relations can be explained using their
  evidence rather than hidden in parser-specific fields.
- Persistent storage can optimize the same graph semantics without owning them.

### Negative

- Legacy calls/imports and typed relations coexist temporarily, so consumers
  must state which representation they read.
- Relation schema changes require additive versioning and snapshot migration
  discipline.
- Provider implementations must normalize facts rather than exposing their
  native graph directly.

## References

- ADR-034: typed relations first for new dataflow facts
- ADR-037: bounded interprocedural dataflow v1 scope
- `plans/007_semidx_extension_architecture_resolution_plan.md`
- `plans/013_open_gaps_closure_program.md`
