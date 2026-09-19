---
title: "Choose Zig as the implementation language"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# 001: Choose Zig As The Implementation Language

## Feature Or Dependency

The from-scratch `semidx` rebuild needs an implementation language for the
semantic graph core, language frontend integration, in-memory indexing, and
incremental reconciliation.

This ADR chooses the implementation language only. Build tooling, dependency
management, source layout, parser bindings, test runner, public contracts,
persistence, services, and release packaging remain separate decisions.

## Decision

Use Zig as the implementation language for the `semidx` rebuild.

The first implementation slice will be a small vertical slice that indexes Java
and Clojure fixtures, extracts semantic entities and `DEFINES`, `REFERENCES`,
and `CALLS` assertions, builds an in-memory semantic graph, distinguishes facts
from unresolved assertions, applies a source edit, and reconciles incrementally
while preserving identity for unchanged entities.

Java and Clojure fixture coverage is a stress test for the shared core and
frontend boundary. It is not a published language coverage claim.

## Rationale

Zig is selected because the first rebuild needs native performance, predictable
local operation, explicit control over memory layout, and direct integration
with parser/frontend dependencies without adopting a heavier runtime boundary
too early.

The key bet is that Zig can keep the semantic model easy to reshape while the
core concepts are still settling. The first vertical slice must therefore test
model change, memory ownership, parser integration, assertion resolution, and
incremental identity preservation together instead of comparing programming
languages in the abstract.

Rust remains a credible alternative for safety and ecosystem maturity, but its
ownership and abstraction costs are not chosen as the default trade-off for the
first rebuild. JVM or Clojure implementation would integrate naturally with
some language-analysis tools, but would move the core away from the intended
native, local, low-service baseline.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Compatible. The chosen language does
   not move authority away from the semantic graph; the first slice must make
   graph assertions the source of semantic answers.
2. **Nodes as entities, not chunks.** Compatible. Zig imposes no chunk-based
   model; the first slice must model source containers and program constructs
   as entities, with source ranges only as evidence or projection.
3. **Facts, unresolved assertions, and approximate assertions stay distinct.**
   Compatible. The implementation must encode resolution and provenance so
   unresolved assertions cannot be presented as facts.
4. **Stable semantic identity across edits.** Compatible. The implementation
   must preserve entity identity through incremental reconciliation when
   correspondence is established, and expose identity loss when it is not.
5. **Incrementality and consistent observation.** Compatible. The first slice
   must update an existing in-memory graph from a source edit rather than
   treating full rebuild as the only model.
6. **Language frontends preserve meaning.** Compatible. Java and Clojure
   frontends must contribute to a common core without making either language's
   constructs define that core.
7. **Consumers do not define the model.** Not directly applicable to the
   language choice because no public consumer is chosen here. Future consumer
   decisions remain bound by the graph model.
8. **Local operation without mandatory source-data transmission.** Compatible.
   Zig supports a fully local process and does not require external services or
   source-derived data transmission.

## Consequences

- Project documentation may now treat Zig as the selected implementation
  language.
- Documents must still avoid claiming a source tree, build tool, test runner, or
  implemented language coverage before those exist.
- Parser/frontend integration decisions should prefer local dependencies and
  preserve frontend-specific semantics at the edge of the shared core.
- If Zig prevents the constitutional properties from being implemented cleanly,
  this ADR must be superseded by a later ADR rather than silently contradicted.

## Verification Evidence And Planned Checks

No implementation evidence exists yet.

The first Zig slice should provide executable checks for:

- entity nodes rather than text chunks;
- `DEFINES`, `REFERENCES`, and `CALLS` assertions from small Java and Clojure
  fixtures;
- at least one unresolved assertion that remains visibly unresolved;
- an incremental source edit applied to an existing graph;
- stable identity for unchanged entities after reconciliation;
- local build, indexing, and query behavior without mandatory external service
  or source-data transmission.
