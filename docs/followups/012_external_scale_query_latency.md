---
title: "External-scale graph query latency"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
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

The root cause is the physical access path, not MCP rendering. A
`Snapshot.relationships` query returns a `RelationshipIterator` over every
assertion in the snapshot, and the source, target, kind, designator, resolution,
and freshness filters are applied inside the iterator. Traversal therefore costs
roughly `frontier * assertions`, so response budgets, `detail`, and
`max_response_bytes` can cap bytes but cannot cap the search work.

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

## Acceptance Direction

A future plan should separate graph authority from graph access paths:

- Keep the graph's assertions, resolution, freshness, producer, and identity
  evidence as the semantic authority.
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

