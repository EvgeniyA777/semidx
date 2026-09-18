---
title: "External-scale graph query indexes"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# 011: External-Scale Graph Query Indexes

## Goal

Make semidx impact-analysis queries interactive at external Java scale without
weakening graph authority.

The user-facing problem is direct: `semidx_context` and `semidx_references` are
the tools an agent reaches for when it asks "who uses this?" and "what would
this edit touch?". On the Plan 010 apache/dubbo probe, definition lookup took
about 0.02 s, references took about 1.3 s, and `semidx_context` at `depth=2`
took about 90 s. That breaks the IDE and agent habit loop even when every fact
returned is honest.

This plan turns the graph's current append-only scan access path into derived
query indexes. The assertions remain the semantic authority; indexes only make
known assertions findable in time proportional to the local neighborhood a query
asks for.

## Product Principle

Prefer the interaction that keeps a developer in flow:

- A focused context query should feel like navigation, not like a batch job.
- Budgets should bound response size, but query latency must be bounded by the
  graph access path before rendering begins.
- When scale forces a trade-off, keep exactness and freshness visible. Return a
  smaller exact answer or an honest degradation before returning a guessed one.
- Do not move complexity into the user interface. The same MCP calls should get
  faster without asking agents or IDE users to choose a storage backend, profile,
  or implementation mode.

## Start Rule

Start only after reading:

- [Follow-up 012](../followups/012_external_scale_query_latency.md)
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md)
- `src/core/graph.zig`, especially `Snapshot.relationships`,
  `RelationshipIterator`, `countRelationships`, and `firstRelationship`
- `src/mcp/tools.zig`, especially `semidx_references` and `semidx_context`

Before code changes, create
`docs/reports/011_external_scale_graph_query_indexes_progress.md` with standard
progress-log frontmatter. Record the baseline commands and any local limitation
there before Stage 1 implementation.

Stop before implementation if the current code no longer has a linear
`Snapshot.relationships` path or if another active plan already owns graph query
storage. In that case, update this plan or cancel it; do not build a second
indexing design beside an existing one.

## Scope

- Add a derived relationship query index for immutable snapshots.
- Make `Snapshot.relationships`, `countRelationships`, and
  `firstRelationship` use indexed candidates for hot filters.
- Preserve every existing graph assertion, entity id, assertion id, resolution,
  freshness, producer, designator, evidence location, and result ordering
  contract that current tests imply.
- Move `semidx_references` and `semidx_context` onto the faster path through the
  existing `Snapshot.relationships` API, not through MCP-specific caches.
- Add a deterministic scale fitness check that exposes the Dubbo failure mode
  without committing external repositories.
- Reuse the same access-path discipline for Java package/import binding if the
  post-relationship-index measurements still show candidate scans dominating the
  write path.
- Update documentation, operational memory, and Follow-up 012 closure state when
  the plan is executed.

## Non-Scope

Do not change MCP tool JSON shape, cursor semantics, response-budget semantics,
or `semantic_contract_version`.

Do not add SQLite, another database, persistence, file watching, daemon state,
HTTP, gRPC, or a storage migration in this plan. SQLite remains a plausible
future backend for the same index contract, not the first implementation.

Do not read Maven, Gradle, class files, `.jar` files, or any build descriptor.
Java semantic coverage and cross-module visibility are owned by separate
follow-ups.

Do not add shared-core `module` or `IMPORTS`. This plan is about physical access
paths over already-authorized graph assertions.

Do not add approximate, vector, text-search, or name-match fallbacks to make
impact analysis look fuller. Faster false confidence is worse than a slow exact
answer.

Do not commit external repositories or use an external repository as a
conformance target. The hard gate must be synthetic and local.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  graph authority, local operation, freshness, and consumer boundaries.
- [MEMORY.md](../../MEMORY.md), for current runtime reality and known risks.
- [Follow-up 012](../followups/012_external_scale_query_latency.md), for the
  accepted product problem and required tests.
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  for the external Java evidence.
- [Testing policy](../agent-policy/testing.md), for risk-based verification.

## Current Evidence

The Plan 010 Dubbo probe indexed 4,050 Java files across 119 Maven modules. It
found that Java truth boundaries were fixed, but product interactivity was not:
`semidx_context` at `depth=2` cost about 90 s against 230,753 assertions.

The immediate cause is `RelationshipIterator.next`: it scans every assertion in
the snapshot and applies `source`, `target`, `kind`, `reference_query`,
`resolution`, `designator`, and `freshness` filters inside the loop. A traversal
therefore costs roughly `frontier * assertions`.

The current `preview-gate` cannot prove this class of behavior. Its
repository-copy profile uses this repository, which has thousands of assertions,
not hundreds of thousands. A timing threshold there would give false comfort at
enterprise scale.

## Architecture Decisions

**Assertions remain the authority.** The index stores assertion ids or offsets
that point back to snapshot assertions. It must be rebuildable from the snapshot
without loss. No query result may exist only in the index.

**The snapshot owns the query index.** Consumers observe `Snapshot`, not mutable
`Graph`, so the first correct place for an immutable query projection is the
published snapshot. `Graph.publish` may pay the build cost once per published
state; individual queries must not rebuild indexes.

**The public API stays centered on `Snapshot.relationships`.** MCP tools,
frontends, tests, and future consumers should keep using one graph query API.
The index is an implementation detail behind the iterator.

**Hot keys come first.** Stage 2 must index at least:

- outgoing relationships by source entity
- incoming relationships by target entity, for entity targets only
- unresolved relationships by designator

Secondary filters such as `kind`, `reference_query`, `resolution`, and
`freshness` may be applied after candidate selection at first. Add compound
indexes only when a measured hot path still scans a large candidate set.

**Fallback is allowed only for unsupported filters.** A relationship query with
no indexed anchor may still scan all assertions. A query with `source`, `target`,
or `designator` must not fall back silently to a full snapshot scan unless the
progress log records a correctness bug and the stage remains incomplete.

**Scale proof uses work, not wall-clock.** Required tests should prove candidate
count or inspected-assertion count deterministically. Timings are useful
observations, but wall-clock thresholds are too flaky for the first hard gate.

**SQLite is deferred by design.** SQLite could later back persistence,
cold-start avoidance, and very large local indexes. It should implement the same
projection contract after the in-memory contract is proven. Adding it now would
mix access-path semantics, lifecycle, dependency policy, and migration behavior
into one plan.

## Architecture Boundaries

1. Core graph
Responsibility: assertions, entities, resolution, freshness, immutable snapshot
publication, and derived relationship query indexes.
Does not know about: MCP response rendering, Java package rules, external
repository choices, or SQL.

2. Relationship index
Responsibility: map indexed query anchors to assertion ids or offsets and expose
candidate iteration without changing assertion meaning.
Does not know about: user-facing budgets, rendering detail levels, language
semantics, or source text.

3. MCP preview
Responsibility: call graph query APIs and render exact results, budgets, and
narrowing hints.
Does not know about: whether candidates came from arrays, hash maps, or a future
database.

4. Java frontend
Responsibility: Java package/import semantics and dependency invalidation.
May receive a language-specific candidate index only after Stage 3 proves the
core relationship path and Stage 4 measurements justify write-path work.

5. Tests and gates
Responsibility: prove semantic parity, deterministic scale behavior, freshness,
incremental publication, and MCP output stability.

## Implementation Stages

### Stage 0: Execution Setup And Baseline

Purpose: make the implementation auditable before touching graph storage.

Likely files:

- `docs/reports/011_external_scale_graph_query_indexes_progress.md`

Required work:

- Run `./scripts/check-zig-version.sh`.
- Record the current git commit, dirty status, and baseline command set in the
  progress log.
- Reproduce the current hot path on a local synthetic graph or existing test
  harness if one already exists. If no harness exists, record that Stage 1 will
  add it; do not use an external repository as the required baseline.
- Record the exact current shape of `RelationshipFilter`.

Done when:

- The progress log exists and names this plan.
- The log records the baseline evidence or explains why the first synthetic
  baseline arrives in Stage 1.

Verification:

- Documentation-only setup may use `git diff --check`.
- No code lane is required until Stage 1 changes code.

### Stage 1: Relationship Index Contract And Oracle Tests

Purpose: create the smallest core abstraction that can be proven against a
linear oracle before any MCP path depends on it.

Likely files:

- `src/core/graph.zig`
- optionally `src/core/relationship_index.zig`
- any core module export needed by the existing build structure

Required behavior:

- Define a relationship-index projection that stores candidates as assertion
  positions or assertion ids pointing back into one snapshot's assertion array.
- Build the projection from a supplied assertion slice. The builder must ignore
  non-relationship assertions for relationship-index keys.
- Support candidate lookup by:
  - source entity id
  - target entity id when the relationship target is an entity
  - designator when the relationship target is unresolved by designator
- Preserve deterministic order. The easiest acceptable rule is snapshot
  assertion order within every candidate list.
- Add a linear oracle in tests that applies `RelationshipFilter` the old way and
  compares returned assertion ids.

Branch handling:

- If the index cannot preserve assertion order cheaply, stop and record the
  ordering conflict. Do not ship a faster path that reorders results unless an
  explicit test and documentation update accepts that behavior.
- If assertion id and assertion-array offset can diverge under current code, use
  offsets internally but compare ids externally. Do not assume id equals offset.

Done when:

- Core unit tests prove candidate lookup for source, target, designator, and
  non-relationship assertions.
- A parity test compares indexed candidates against the linear oracle for mixed
  filters, including `kind`, `reference_query`, `resolution`, `freshness`, and
  both fact and unresolved relationships.

Verification:

- `zig build test-core`
- `zig fmt --check build.zig src tests`

### Stage 2: Snapshot Integration

Purpose: make the existing graph query API use the index without changing
callers.

Likely files:

- `src/core/graph.zig`
- optionally `src/core/relationship_index.zig`

Required behavior:

- Add the relationship index to `Snapshot` lifetime management.
- Build the index during snapshot publication after snapshot assertions are in
  their final immutable order.
- Change `Snapshot.relationships(filter)` so it selects the narrowest available
  candidate source:
  - `target` if present and indexed
  - `source` if present and indexed
  - `designator` if present and indexed
  - full assertion scan only when no indexed anchor exists
- When multiple indexed anchors are present, choose the smaller candidate list
  and apply the remaining filters during iteration. If candidate-list size is
  not available cheaply, make it available; do not guess based on field order.
- Keep `countRelationships` and `firstRelationship` as callers of
  `relationships`, so they inherit the same path.
- Keep `freshness` filtering exactly as today. If the index stores stale
  candidates, filtering them out during iteration is acceptable; publishing a
  mixed current/stale answer is not.

Branch handling:

- If memory ownership for the index makes `Snapshot.deinit` ambiguous, stop and
  split the index into an explicitly owned struct before continuing.
- If any existing test observes a result-order change, treat it as a bug unless
  the progress log records why old ordering was accidental and the user-facing
  output remains stable.
- If an anchor lookup returns no candidate list, return an empty iterator for
  that anchored query. Do not fall back to a full scan looking for the same
  source, target, or designator.

Done when:

- Existing core tests pass unchanged or with only expectation changes justified
  by documented order behavior.
- A test proves a missing indexed source/target/designator returns zero results
  without scanning all assertions.
- A test proves snapshot publication after edits rebuilds or refreshes the index
  so stale graph state is not mixed with current graph state.

Verification:

- `zig build test-core`
- `zig fmt --check build.zig src tests`

### Stage 3: MCP Hot Path Parity

Purpose: make the product-facing tools faster through the core API while keeping
their public shape stable.

Likely files:

- `src/mcp/tools.zig`
- `src/core/graph.zig`
- MCP tests under the current test layout

Required behavior:

- Keep `semidx_references` and `semidx_context` output schemas unchanged.
- Do not add tool arguments for index mode, storage mode, or performance
  profiles.
- Ensure references' incoming and outgoing passes use indexed `target` and
  `source` filters.
- Ensure context traversal uses indexed incoming/outgoing relationship passes at
  every frontier step.
- Preserve de-duplication behavior for recursive calls, repeated targets, and
  already listed relationships.
- Preserve budget behavior: `limit`, `detail`, and `max_response_bytes` still
  cap returned content, not search work.

Branch handling:

- If an MCP test failure is only ordering, compare against Stage 2's documented
  snapshot assertion order. Fix the implementation if the new order is not that
  order.
- If MCP code was bypassing `Snapshot.relationships` somewhere, route it through
  the core API unless doing so loses required information. Record any exception
  in the progress log and add a focused test.

Done when:

- Existing MCP tests pass.
- At least one focused MCP test or fixture proves `semidx_context depth=2`
  returns the same structured relationship ids before and after the index path.
  If no pre-index fixture is retained, use the linear oracle in the test.

Verification:

- `zig build test-mcp`
- `zig build test`
- `zig fmt --check build.zig src tests`

### Stage 4: Deterministic External-Scale Fitness Check

Purpose: prove the Dubbo failure mode is gone without depending on Dubbo or any
other external repository.

Likely files:

- `src/core/graph.zig` or a new core test file
- optionally `src/mcp/` tests if the existing test harness can exercise a
  synthetic snapshot without a subprocess
- `docs/mcp/habit_loop_gate.md` only if the gate's documented observations
  change

Required behavior:

- Add a synthetic graph with hundreds of thousands of assertions or the nearest
  local size that keeps `zig build test-core` practical. The graph must include:
  - many unrelated relationships
  - a small anchored incoming neighborhood
  - a small anchored outgoing neighborhood
  - a depth-2 shape where the frontier expands but remains tiny relative to the
    assertion count
  - unresolved designator relationships
  - stale assertions mixed with current assertions
- Prove indexed anchored queries inspect only candidate lists plus necessary
  filter checks, not the full assertion set per frontier entity.
- Prefer a deterministic inspected-candidate counter or test-only iterator
  statistic over timing. Timing may be printed or recorded in the progress log
  as an observation, but it must not be the only hard proof.
- Add a regression test that would fail under the old
  `frontier * assertions` scan path.

Branch handling:

- If a 230k-assertion synthetic test is too heavy for the required local lane,
  keep the hard test deterministic at the largest practical size, record the
  measured ceiling in the progress log, and add a separate non-default command
  for larger local scale. Do not fake scale by lowering the acceptance claim.
- If adding a scale test to `zig build test-core` makes the normal lane
  materially slower, split the size: a small deterministic proof in
  `test-core`, and a named scale lane documented in this plan's progress log.

Done when:

- The test suite contains a deterministic proof that anchored relationship and
  depth-2 traversal work do not grow with total assertion count per frontier
  step.
- The progress log records observed time and memory on the synthetic scale
  shape, while making clear that the hard assertion is the work bound.

Verification:

- `zig build test-core`
- `zig build test-mcp` if Stage 4 adds MCP coverage
- `zig build preview-gate` after the hard proof exists, even if preview-gate
  remains observational for latency
- `zig fmt --check build.zig src tests`

### Stage 5: Java Write-Path Access-Path Review

Purpose: decide, with measurements after the core query fix, whether Java
package/import binding needs its own derived candidate index in this plan.

Likely files if implementation is needed:

- `src/frontends/java*.zig`
- Java package helper files such as `src/frontends/java_packages.zig`
- Java frontend tests and fixtures

Required work:

- Measure Java indexing on the same kind of workload Plan 010 used or on the
  largest available local Java fixture. Record whether package/import candidate
  scans still dominate ingestion after Stages 1-4.
- If package/import scans are not a meaningful share of ingestion anymore,
  record "deferred, not needed for this plan's product goal" in the progress
  log and skip code changes in Stage 5.
- If scans still matter, add a Java-specific derived projection for package and
  single-type-import lookup. It must be rebuilt from Java frontend evidence and
  must not create facts independently of ADR 004 and ADR 008 rules.
- Keep declarer and importer hint cleanup together. `Packages.note` and the
  Stage 4 importer pattern from Plan 010 share the same stale-hint risk.

Branch handling:

- If the proposed Java index needs build-descriptor knowledge, stop and defer to
  Follow-up 011. Do not smuggle module semantics into an access-path patch.
- If an optimization would merge out-of-scope names with missing names, reject
  it. Plan 010 explicitly made those reasons distinct.
- If the Java write-path optimization increases semantic complexity more than it
  improves measured ingestion, defer it and keep this plan focused on product
  query latency.

Done when either:

- The progress log records that Java write-path indexing is not needed for this
  plan after measurement, or
- Java tests prove the new candidate projection preserves facts, ambiguity,
  out-of-scope names, missing names, single-type imports, provider removal, and
  importer reanalysis.

Verification:

- If no Java code changes: rerun the latest passing Stage 4 command set and
  record the measurement.
- If Java code changes: `zig build test`, `zig build dogfood`, and
  `zig fmt --check build.zig src tests`.

### Stage 6: Documentation And Follow-Up Closure

Purpose: make the new access-path contract visible to the next agent without
turning implementation notes into architecture folklore.

Likely files:

- `docs/reports/011_external_scale_graph_query_indexes_progress.md`
- `docs/followups/012_external_scale_query_latency.md`
- `docs/followups/README.md`
- `MEMORY.md`
- maybe `docs/mcp/habit_loop_gate.md`
- maybe release notes only if a preview release is being prepared

Required behavior:

- Mark Follow-up 012 fixed only if Stages 1-4 are implemented, verified, and the
  product hot path is indexed. If Stage 5 is deferred by measurement, that does
  not block closing Follow-up 012 unless Java ingestion remains the dominant
  product wait.
- Update `MEMORY.md` with the current reality, not a changelog entry.
- Record the final verification commands, pass/fail results, and residual risks
  in the progress log.
- If the scale proof adds a named command or changes preview-gate expectations,
  update the gate documentation in the same commit.

Done when:

- Plan status, follow-up status, memory, and progress log agree.
- No open document says relationship/context queries still require indexed
  access paths unless a residual risk explains the remaining gap.

Verification:

- `zig build test-core`
- `zig build test`
- `zig build test-mcp`
- `zig build dogfood`
- `zig build preview-gate`
- `zig fmt --check build.zig src tests`
- `scripts/check-agent-attribution.sh`

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Relationship indexes are projections only | Index becomes independent authority | Core unit | Returned assertions are loaded from snapshot storage | Index key exists for an assertion removed or not in snapshot | Stage 1 parity tests |
| Anchored relationship queries avoid full scans | Product latency remains `frontier * assertions` | Core unit with synthetic scale | Candidate count stays local for `source`, `target`, and `designator` | Missing anchor returns empty without fallback scan | Stage 2 and Stage 4 work-bound tests |
| MCP output shape remains stable | Existing clients break | MCP integration | Same fields and relationship ids for references/context | Budget exhaustion and pagination still render as before | Stage 3 `zig build test-mcp` |
| Freshness and resolution remain visible | Stale or unresolved claims appear current | Core and MCP tests | Filters preserve `.current`, stale, fact, unresolved, approximate categories | Mixed stale/current synthetic graph | Stage 1, Stage 2, Stage 4 tests |
| Incremental publication is coherent | Snapshot has assertions from one state and index from another | Core integration | Publish/rebuild creates one immutable indexed snapshot | Refresh failure keeps previous snapshot | Stage 2 tests plus existing refresh tests |
| Java write-path optimization does not widen semantics | Faster indexing creates false Java facts | Frontend fixture | ADR 004/008 facts unchanged | Out-of-scope, ambiguous, missing, provider removal, importer reanalysis | Stage 5 tests if implemented |
| Scale fitness is meaningful locally | Gate misses enterprise-scale failure again | Synthetic core test | Hundreds of thousands or documented largest practical assertion count | Old linear path would exceed inspected-work bound | Stage 4 hard proof |
| No new external service dependency | Local/offline guarantee weakens | Documentation and build review | No SQLite or service startup in required lanes | Missing database has no effect because none is required | Stage 6 docs and normal test lanes |

## SQLite Position

SQLite is a credible future backend, but not the first move.

Use it later if the product needs persistent cold-start avoidance, memory-bounded
very large local repositories, or multi-process read access. When that happens,
the design should treat SQLite tables as storage for graph assertions and
derived projections. It must not let SQL rows decide semantic truth that the
graph cannot prove.

This plan intentionally proves the smaller contract first: given one immutable
snapshot in memory, relationship queries have indexed access paths. That keeps
the user-visible win close to the measured pain, keeps tests local and cheap,
and leaves a clean interface for a later SQLite-backed implementation.

## Final Acceptance Criteria

The plan is complete when:

- `semidx_references` and `semidx_context` use indexed relationship access for
  source, target, and designator anchored work.
- A deterministic synthetic scale proof shows depth-2 relationship traversal is
  bounded by local candidates, not by all assertions per frontier entity.
- Existing semantic guarantees for ids, freshness, resolution, producer,
  evidence, and designators are unchanged.
- Follow-up 012 is closed or explicitly narrowed to a remaining storage or Java
  write-path concern.
- The progress log records final commands, results, residual risk, and commits.
