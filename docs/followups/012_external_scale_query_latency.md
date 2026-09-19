---
title: "External-scale graph query latency"
doc_type: "follow_up"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-18"
---

# External-Scale Graph Query Latency

## Classification

`performance_gap`

## Source

Post-closure architecture review of
[Plan 010](../plans/010_java_resolution_boundaries.md), using the external Java
probe recorded in
[Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md).

## Current Behavior

The graph is semantically honest but not yet interactive at external scale.
Against apache/dubbo at `df9c5e1` (119 Maven modules, 4,050 Java source units),
orientation and definition lookup were fast, but impact-style context was not:
`semidx_find_definitions` cost about 0.02 s, `semidx_references` about 1.3 s,
and `semidx_context` at `depth=2` about 90 s.

The root cause is the physical access path, not MCP rendering, and it has two
independent terms.

**Identity lookup, paid per assertion visited.** `Snapshot.publish` copies only
live entities and units, so the `id == position` relation `Graph` relies on does
not hold in `Snapshot`: `Snapshot.unit` and `Snapshot.entityById` are linear
scans. `RelationshipIterator.next` applies the `freshness` filter first, for
every assertion, and that filter calls `assertionFreshness` → `freshnessAt` →
`Snapshot.unit`. Freshness defaults to `.current`, so this is always on.

**Candidate selection, paid per query.** `Snapshot.relationships` iterates every
assertion in the snapshot and applies the source, target, kind, designator,
resolution, and freshness filters inside the loop.

Traversal therefore costs roughly `frontier * assertions * units`, not
`frontier * assertions`. Response budgets, `detail`, and `max_response_bytes` can
cap bytes but cannot cap either term of the search work.

`semidx_health` is the case that separates the two: it walks no relationships at
all, so only the identity-lookup term explains its 2.96 s. It is also step 1 of
the documented habit loop.

The same missing access-path family also affects indexing work. Java package and
single-type-import binding lookup currently relies on package/import hints and
linear scans of candidate sets. Stage 4's import expansion increased ingestion
time because reads of graph-derived relationship context remained linear enough
to matter.

## Product Impact

The strongest adoption question is impact analysis: "who refers to this, and
what would this edit break?" A 90 s focused-context call breaks the agent and
IDE habit loop even when the answer is semantically correct.

At enterprise scale this is not a constant-factor problem. A repository with
hundreds of thousands or a million source units can produce assertion counts far
beyond the Dubbo probe. A query path that scans the whole assertion set for each
frontier entity will stop being a preview limitation and become a product
blocker.

The current `preview-gate` cannot expose this class of defect. It runs over a
copy of this repository and a fixture root, not an external-scale graph. The
repository-copy profile has thousands of assertions, not the hundreds of
thousands measured in the Dubbo probe. A latency threshold on that corpus would
not prove the access path is acceptable at adoption scale.

## Why Deferred

Plan 010 was about Java resolution truth, not physical query storage. It needed
to decide whether cross-boundary Java facts were permitted and to keep false
facts out of the graph. The plan correctly recorded the latency finding as
out-of-scope instead of mixing a graph-storage redesign into a Java semantic
boundary plan.

## Resolution

**Completed by [Plan 011](../plans/011_external_scale_graph_query_indexes.md)**
([report](../reports/011_external_scale_graph_query_indexes_progress.md)).

Both terms named below were removed, and neither was traded against exactness.
A published snapshot derives dense id-to-position tables for identity lookups
and compressed-sparse-row adjacency by source entity, target entity, and
designator for relationship queries. They are projections of that snapshot's own
assertions: no result exists only in an index, an anchor the index does not hold
returns empty rather than falling back to a scan, and every other filter stays a
post-filter. Parity against the pre-index path is asserted on assertion ids and
order, and at the MCP surface by comparing responses byte for byte.

Two departures from the direction below are deliberate and recorded here rather
than left to be noticed.

**The latency gate became a work bound.** The direction asked for a gate
recording latency on a scale fixture. Plan 011's D9 replaced it: the committed
assertion is an inspected-candidate count, because a timing threshold would make
the lane unreliable for every later agent while proving less. The proof runs at
244,559 assertions, past the 230,753 measured on apache/dubbo, and fails under
the access path it replaced.

**Java write-path work was measured and declined.** Refresh after a one-file
edit costs 13 ms at 1,200 Java units and is indistinguishable from a refresh
that analyzes nothing; the units reanalyzed when a package's exports change is
constant at 41 across a doubling of the corpus. Nothing in the write path grows
faster than linearly in units, so no candidate projection was added.

One thing this closure does **not** claim: the equivalent latency on apache/dubbo
was not re-measured. The claim rests on the work bound, not on a new wall clock.
Re-running the Plan 010 probe would close that, and is recorded as the next step
in `MEMORY.md`.

Persistence is untouched and stays open as a separate question; see
[SQLite Position](../plans/011_external_scale_graph_query_indexes.md#sqlite-position).

## Acceptance Direction

Implementation plan:
[Plan 011: External-Scale Graph Query Indexes](../plans/011_external_scale_graph_query_indexes.md).

A future plan should separate graph authority from graph access paths:

- Keep the graph's assertions, resolution, freshness, producer, and identity
  evidence as the semantic authority.
- Give the snapshot constant-time identity lookups first. It is the smaller fix,
  it changes no signature and no result, and it is the term that explains
  `semidx_health`, which no adjacency index can help.
- Add derived query indexes that can always be rebuilt from that authority:
  outgoing relationships by source entity, incoming relationships by target
  entity, and whatever secondary keys the measured hot paths need, such as kind,
  freshness, designator, unit, package, or Java source root.
- Move `semidx_references` and `semidx_context` onto indexed adjacency access so
  their cost is proportional to the local neighborhood they return, not to every
  assertion in the repository.
- Reuse the same access-path design for Java package and import binding lookups
  where measurements show candidate scans dominate write-path cost.
- Add a scale fitness check that can observe the failure mode. Because committed
  external repositories are intentionally not conformance targets, the likely
  first step is a synthetic graph fixture with hundreds of thousands of
  assertions and a depth-2 traversal budget.

SQLite may be a good future storage and query-index backend, especially for
persistence, cold-start avoidance, and very large local repositories. It must not
become the semantic authority: SQLite rows would store or index graph assertions
and projections, not establish facts. The first latency fix may still be an
in-memory adjacency index, because it proves the access-path contract with the
least storage and migration risk. A later persistence plan can choose whether
SQLite backs the same contract.

## Required Tests

- A synthetic graph with external-scale assertion counts proves that incoming,
  outgoing, and depth-2 context queries do not scan the full assertion set per
  frontier entity.
- `semidx_references` and `semidx_context` preserve every claim's resolution,
  freshness, producer, evidence location, and designator behavior after moving
  to indexed access.
- Incremental edits update or rebuild the derived indexes without publishing a
  mixed graph state.
- Java package and import binding tests continue to distinguish facts,
  ambiguous names, out-of-scope names, and missing names.
- A gate records latency on the scale fixture. Thresholds are tied to the
  synthetic graph size and query shape, not to this repository's dogfood size.
