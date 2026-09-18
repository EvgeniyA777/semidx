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

Make semidx answer impact questions at external Java scale fast enough to stay
in an agent's habit loop, without weakening graph authority.

On the Plan 010 apache/dubbo probe (4,050 units, 230,753 assertions):
`semidx_find_definitions` 0.02 s, `semidx_health` 2.96 s, `semidx_references`
1.33 s, `semidx_context` at `depth=2` 90.71 s. Every answer was honest. None of
the last three is interactive.

This plan changes only how known assertions are *found*. It adds no assertion,
removes none, and changes no claim's resolution, freshness, producer, or
evidence.

## Product Principle

When a stage offers a choice, decide in this order:

1. **Exactness is not negotiable.** A faster answer that is less exact, or that
   hides how far a claim was resolved, is not an improvement. Return a smaller
   exact answer or an honest degradation before a guessed one.
2. **The habit loop is the product.** `semidx_health` → `semidx_outline` →
   `semidx_repo_map` → `semidx_find_definitions` → `semidx_references` /
   `semidx_context` is the documented loop. A step that takes seconds gets
   replaced by `grep`, and then the graph stops being used at all.
3. **No new surface for the user.** No tool argument, profile, storage mode, or
   flag for performance. The same calls get faster.
4. **Cheapest sufficient fix first, measured each time.** Fix the dominant term,
   re-measure, then decide whether the next term is still worth work.

## Start Rule

Read before starting:

- [Follow-up 012](../followups/012_external_scale_query_latency.md)
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md),
  for the measurements this plan is built on
- `src/core/graph.zig`: `Snapshot`, `publish`, `RelationshipIterator`,
  `Snapshot.unit`, `Snapshot.entityById`, `freshnessAt`
- `src/mcp/tools.zig`: `semidx_references` and `semidx_context`

Create `docs/reports/011_external_scale_graph_query_indexes_progress.md` with
standard progress-log frontmatter before the first code change.

Stop and re-open this plan if Stage 0 measurement contradicts the cost model in
[Current Evidence](#current-evidence) — for example if identity lookups turn out
not to dominate. The stage order below follows from that model; if the model is
wrong, the order is wrong.

## Scope

- Make snapshot identity lookups (`unit`, `entityById`) constant-time.
- Add a derived relationship adjacency index to `Snapshot` for source-entity,
  target-entity, and designator anchored queries.
- Route `Snapshot.relationships`, `countRelationships`, and `firstRelationship`
  through it without changing their signatures or result contracts.
- Add a deterministic, work-bound scale proof on a synthetic graph.
- Measure the Java write path afterwards and fix it only if it still dominates.
- Update documentation, `MEMORY.md`, and Follow-up 012 on closure.

## Non-Scope

Do not change MCP tool JSON shape, tool arguments, cursor semantics,
response-budget semantics, or `semantic_contract_version`.

Do not add SQLite, any database, persistence, file watching, a daemon, HTTP, or
a storage migration. SQLite stays a candidate backend for the same contract
later; see [SQLite Position](#sqlite-position).

Do not add approximate, vector, text-search, or name-match fallbacks. Faster
false confidence is worse than a slow exact answer.

Do not change Java, Clojure, or Zig resolution rules. Stage 5 may change how
Java *finds* candidates, never which candidates are facts.

Do not commit an external repository or make one a conformance target. The hard
gate is synthetic and local.

Do not add shared-core `module` or `IMPORTS`.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  §1 graph authority, §3 exactness, §5 incrementality and consistent
  observation, §7 consumers, §8 local operation.
- [MEMORY.md](../../MEMORY.md), for current runtime reality.
- [Follow-up 012](../followups/012_external_scale_query_latency.md).
- [Plan 010 progress](../reports/010_java_resolution_boundaries_progress.md).
- [Testing policy](../agent-policy/testing.md).

## Current Evidence

There are **two independent costs**, and they must not be conflated.

**Cost 1 — identity lookup, paid per assertion visited.** `Snapshot.publish`
copies only live entities and units, so the `id == position` relation that
`Graph` relies on does not hold in `Snapshot`. `Snapshot.unit(id)` and
`Snapshot.entityById(id)` are linear scans. `RelationshipIterator.next` applies
the `freshness` filter first, for every assertion, and that filter calls
`assertionFreshness` → `freshnessAt` → `Snapshot.unit(id)`. Freshness defaults
to `.current`, so this is always on.

**Cost 2 — candidate selection, paid per query.** `Snapshot.relationships`
returns an iterator over *every* assertion and applies `source`, `target`,
`kind`, `reference_query`, `resolution`, and `designator` inside the loop.

Together the traversal cost is about `frontier × assertions × units`, not
`frontier × assertions`. The model reproduces every Plan 010 measurement:

| Call | Predicted work | Measured |
| --- | --- | --- |
| `semidx_find_definitions` (`name` + `path`) | no assertion walk | 0.02 s |
| `semidx_health` | ~3 × assertions × unit scan, **no traversal** | 2.96 s |
| `semidx_references` | ~2 × assertions × unit scan | 1.33 s |
| `semidx_context` `depth=2` | frontier × the above | 90.71 s |

`semidx_health` is the decisive case: it walks no relationships at all, so an
adjacency index cannot help it. Only Cost 1 explains it. It is also step 1 of the
documented habit loop.

Order follows from this. Cost 1 is a few dozen lines, changes no signature, and
cannot change results. Cost 2 is structural. Fix Cost 1 first and re-measure.

The current `preview-gate` cannot observe either: its repository-copy profile has
about 5,486 assertions against Dubbo's 230,753, and at `O(assertions × units)`
the gap is roughly three orders of magnitude.

## Architecture Decisions

These are decisions, not open questions. An executing agent applies them.

**D1 — Assertions remain the authority.** Every index stores positions into the
snapshot's own assertion array and is rebuildable from it with no loss. No query
result may exist only in an index. This keeps §1 and §3 intact: an index makes a
recorded claim findable, it never establishes one.

**D2 — The snapshot owns every index, built eagerly in `publish`.** Not lazily.
`Snapshot.relationships` takes `*const Snapshot`, so a lazy build would need
interior mutability, which would mean either a mutable published state or a lock
— both at odds with §5's "one consistent state per query". Build cost is
`O(assertions)` once per published state, against the `O(assertions × units)` per
*query* it removes.

**D3 — Identity lookups are position tables.** In `publish`, build
`unit_positions` and `entity_positions`: dense `[]u32` indexed by
`id.index()`, holding the position in the published slice, with a sentinel for
absent. Sized by the highest live id plus one. On the Dubbo shape that is about
4 × 4,050 + 4 × 26,509 ≈ 122 KB. `Snapshot.unit`, `Snapshot.entityById`, and
`Snapshot.unitAnalysis` read them; their signatures and return types do not
change.

**D4 — Adjacency is compressed sparse row, not a map of lists.** Two passes over
the assertion array: count per key, then fill. One allocation per index, no
per-key allocation, and bucket contents come out in snapshot assertion order by
construction — so **result ordering is preserved by design and is not a branch**.
Three indexes:

- outgoing: keyed by `source` entity position
- incoming: keyed by `target` entity position, entity targets only
- designator: a `StringHashMap` from designator to a position list, since string
  keys have no dense space

**D5 — Anchor selection is explicit and never silently falls back.**
`Snapshot.relationships` picks candidates in this order: if `target` and `source`
are both given, take the shorter candidate list (CSR gives length in O(1)); else
`target`; else `source`; else `designator`; else the full assertion array. A
query anchored on `source`, `target`, or `designator` whose key is absent returns
an **empty** iterator — never a full scan looking for the same thing.

**D6 — Every other filter stays a post-filter.** `kind`, `reference_query`,
`resolution`, and `freshness` are applied per candidate as today. No compound
index until Stage 4 measurement shows a hot path still scanning a large candidate
list. Freshness stays exactly as strict; after D3 it is O(1) per candidate.

**D7 — `target` and `designator` are disjoint and stay disjoint.** A relationship
target is either an entity or a designator. The `target` filter already skips
designator targets and the `designator` filter skips entity targets. The incoming
index therefore indexes entity targets only, the designator index indexes
designator targets only, and `reference_query` — which spans kinds, not target
shapes — remains a post-filter over whichever anchor was chosen.

**D8 — Memory budget.** The indexes must add no more than 10% to peak RSS on the
Dubbo-shaped synthetic graph. If they do, drop the designator index first (it is
the least used anchor) and record the measurement. Local operation under §8
includes fitting on the developer's machine.

**D9 — Scale proof is a work bound, not a clock.** The hard assertion is an
inspected-candidate count from a test-only counter. Wall-clock times are recorded
as observations in the progress log. Timing thresholds are too flaky to gate on
and would make the lane unreliable for every future agent.

**D10 — The write path is a different problem and is diagnosed separately.**
Stage 4's Plan 010 ingestion cost (17.5 s → 21.5 s) comes from
`java_packages.importBindings` calling `exportsOf` per candidate unit against the
mutable `Graph`. The snapshot indexes do not exist there. Stage 5 measures it on
its own terms and may decide to do nothing.

## Architecture Boundaries

1. **Core graph.** Owns assertions, entities, freshness, immutable snapshot
publication, and the derived lookup and adjacency indexes. Does not know about
MCP rendering, Java rules, or SQL.

2. **Snapshot indexes.** Map an anchor to candidate positions. Do not know about
budgets, detail levels, language semantics, or source text.

3. **MCP preview.** Calls the same graph query API and renders. Does not know
whether candidates came from an array, a CSR index, or a future database. No
tool shape changes.

4. **Java frontend.** Owns package and import semantics and invalidation. May get
its own candidate projection in Stage 5, only if measured, and only over evidence
ADR 004 and ADR 008 already authorize.

5. **Tests and gates.** Prove semantic parity against a linear oracle,
deterministic work bounds, freshness, and coherent publication.

## Implementation Stages

### Stage 0: Baseline And Harness

Purpose: make every later claim comparable to a number recorded first.

Likely files:

- `docs/reports/011_external_scale_graph_query_indexes_progress.md`
- a new core test file for the synthetic graph builder

Required work:

- Run `./scripts/check-zig-version.sh`; record commit and worktree state.
- Add a **synthetic graph builder** usable from core tests: parameterised by unit
  count, entity count, and assertion count, producing a graph with unrelated
  relationships, a small anchored incoming neighbourhood, a small anchored
  outgoing neighbourhood, a depth-2 shape whose frontier stays tiny relative to
  the assertion count, unresolved designator relationships, and stale assertions
  mixed with current ones. This is the required baseline; it is local,
  deterministic, and committed.
- Record baseline inspected-work counts and wall-clock for: `countAssertions`
  with the default freshness filter, an anchored `relationships` query, and a
  depth-2 traversal shape, at the largest size that keeps `zig build test-core`
  practical.
- Reproducing the Dubbo numbers is **optional and never a gate**. If done, record
  the clone commit and treat it as one observation, consistent with Plan 010's
  decision to keep external repositories out of conformance.

Done when:

- The progress log names this plan and records baseline numbers from the
  synthetic graph.
- The builder is committed and used by at least one test.

Verification: `zig build test-core`, `zig fmt --check build.zig src tests`.

### Stage 1: Constant-Time Identity Lookups

Purpose: remove Cost 1, the term that explains `semidx_health` and multiplies
everything else.

Likely files:

- `src/core/graph.zig`

Required behavior:

- Build `unit_positions` and `entity_positions` in `publish` per D3.
- `Snapshot.unit`, `Snapshot.entityById`, and `Snapshot.unitAnalysis` read them.
  Signatures, return types, and null behavior are unchanged.
- `Snapshot.deinit` frees them. They are owned like every other snapshot slice.
- `unitByPath` and `findEntity` stay as they are: they are not on the per-
  assertion path, and changing them is out of scope.

Branch handling:

- If a live id exceeds what a dense table can size cheaply — for example after
  heavy churn in a long session — keep the dense table sized by the highest live
  id and treat any id beyond it as absent. Do not silently fall back to a scan:
  a scan here is the defect being removed.
- If any test observes a behavior change, it is a bug in this stage, not an
  expectation to update. These functions must return exactly what they returned
  before.

Done when:

- A core test proves `unit` and `entityById` return the same results as a linear
  reference implementation over a graph with removed units and entities, so the
  id/position gap is actually exercised.
- The Stage 0 `countAssertions` baseline improves, and the new number is
  recorded. This is the stage's own evidence that the cost model was right.

Verification: `zig build test-core`, `zig build test`,
`zig fmt --check build.zig src tests`.

### Stage 2: Relationship Adjacency Index

Purpose: remove Cost 2 for anchored queries.

Likely files:

- `src/core/graph.zig`, optionally `src/core/relationship_index.zig`

Required behavior:

- Build the three CSR indexes per D4 in `publish`, after the assertion array is
  in its final order.
- `Snapshot.relationships` selects candidates per D5 and applies remaining
  filters per D6.
- `countRelationships` and `firstRelationship` keep calling `relationships` and
  inherit the path unchanged.
- Non-relationship assertions are skipped when building relationship keys.

Branch handling:

- Ordering is settled by D4 and is not a decision to revisit. If observed order
  changes, the build walked the assertions out of order — fix the build.
- Assertion id and array position may diverge; index positions internally and
  compare ids in tests.
- If index ownership makes `Snapshot.deinit` ambiguous, put the indexes in one
  explicitly owned struct with its own `deinit` before continuing.

Done when:

- A parity test compares indexed results against a linear oracle applying the old
  filter logic, over mixed filters including `kind`, `reference_query`,
  `resolution`, both freshness values, fact and unresolved relationships, and
  entity and designator targets. It compares assertion ids **and order**.
- A test proves an absent anchor returns empty without inspecting the full
  assertion array.
- A test proves publication after an edit yields one snapshot whose indexes match
  its own assertions — never a mix of two states.

Verification: `zig build test-core`, `zig build test`,
`zig fmt --check build.zig src tests`.

### Stage 3: MCP Hot Path Parity

Purpose: deliver the win to the tools users actually call, with no visible
change other than speed.

Likely files:

- `src/mcp/tools.zig`, MCP tests

Required behavior:

- `semidx_references` incoming and outgoing passes use `target` and `source`
  anchors.
- `semidx_context` uses anchored passes at every frontier step.
- Output schemas, field order, de-duplication, traversal rendering, cursors, and
  budget behavior are unchanged.
- No new tool argument (Product Principle 3).

Branch handling:

- If MCP code reaches past `Snapshot.relationships` anywhere, route it through
  the core API; record any exception in the progress log with a focused test.
- If an MCP test fails only on ordering, the implementation is wrong, not the
  test: D4 fixes the order.

Done when:

- `zig build test-mcp` and `zig build test` pass with no expectation changes.
- A focused test proves `semidx_context` at `depth=2` returns the same structured
  relationship ids, in the same order, as the linear oracle.

Verification: `zig build test-mcp`, `zig build test`,
`zig fmt --check build.zig src tests`.

### Stage 4: Deterministic Scale Proof

Purpose: make this failure mode impossible to reintroduce silently.

Likely files:

- core test file from Stage 0, optionally `docs/mcp/habit_loop_gate.md`

Required behavior:

- Add a test-only inspected-candidate counter on the iterator.
- Assert, on the Stage 0 synthetic graph, that anchored queries and depth-2
  traversal inspect work proportional to the local neighbourhood, not to total
  assertions per frontier step. The assertion must fail under the pre-Stage-2
  path.
- Record wall-clock and peak memory as observations, and check the D8 memory
  budget.
- Keep `zig build test-core` practical: if the largest meaningful size makes the
  default lane materially slower, keep a smaller deterministic proof in
  `test-core` and put the larger size behind a named command documented in the
  progress log. Do not lower the acceptance claim to fit the lane.

Done when:

- The suite contains a work-bound proof that would fail under the old path.
- The progress log records observed time, memory, and the measured index size
  against D8.

Verification: `zig build test-core`, `zig build test`, `zig build preview-gate`,
`zig fmt --check build.zig src tests`.

### Stage 5: Java Write-Path Measurement

Purpose: decide with numbers whether the write path still needs work.

Required work:

- Re-measure Java ingestion after Stages 1–4, on the largest available local Java
  fixture or a fresh external clone recorded as an observation.
- Compare against Plan 010's 17.5 s → 21.5 s. Per D10 the cause is
  `importBindings` calling `exportsOf` per candidate unit against `Graph`, so
  Stages 1–4 may not have moved it at all.
- **If import/package candidate scans are no longer a meaningful share of
  ingestion, record that and change no code.** Skipping is a valid, expected
  outcome.
- If they still dominate, add a Java-side candidate projection rebuilt from Java
  frontend evidence. It must not create, widen, or reorder facts: ADR 004 and
  ADR 008 rules are untouched.

Branch handling:

- If a proposed optimization would need build-descriptor knowledge, stop; that is
  [Follow-up 011](../followups/011_java_cross_module_visibility.md).
- If an optimization would merge out-of-scope names with missing names, reject
  it. Plan 010 made those reasons distinct on purpose.
- If it adds more semantic complexity than measured ingestion it saves, defer it.

Done when either the progress log records that no change is needed, or Java tests
prove facts, ambiguity, out-of-scope names, missing names, single-type imports,
provider removal, and importer reanalysis all behave exactly as before.

Verification: if no code changes, rerun Stage 4's command set and record the
measurement. If code changes: `zig build test`, `zig build dogfood`,
`zig fmt --check build.zig src tests`.

### Stage 6: Documentation And Closure

Likely files:

- the progress log, `docs/followups/012_external_scale_query_latency.md`,
  `docs/followups/README.md`, `MEMORY.md`, maybe
  `docs/mcp/habit_loop_gate.md`

Required behavior:

- State in `MEMORY.md` that snapshot identity lookups and anchored relationship
  queries are indexed, as current reality rather than a changelog entry.
- Record the final latency numbers next to Plan 010's, so the before and after
  are readable together.
- Close Follow-up 012 if Stages 1–4 landed and the hot path is indexed; narrow it
  if a storage or write-path concern remains.
- If the scale proof adds a named command or changes gate expectations, update
  the gate documentation in the same commit.

Done when plan status, follow-up status, `MEMORY.md`, and the progress log agree,
and no document still describes the linear query path as current.

Verification: `./scripts/check-zig-version.sh`,
`zig fmt --check build.zig src tests`, `zig build test-core`, `zig build test`,
`zig build test-mcp`, `zig build dogfood`, `zig build preview-gate`.

## Risk Matrix

| Guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Indexes are projections only | An index becomes independent authority | Core unit | Results are read from snapshot assertions | Key present for an assertion not in the snapshot | Stage 2 parity |
| Identity lookups unchanged in meaning | A wrong unit or entity silently changes freshness | Core unit | Same results as a linear reference, over a graph with removals | Id beyond the table is absent, not scanned | Stage 1 |
| Anchored queries avoid full scans | Latency stays multiplicative | Core unit, synthetic scale | Inspected work is local | Absent anchor returns empty without a scan | Stages 2 and 4 |
| Result order stable | Clients and tests see reordered output | Core and MCP | CSR built in assertion order | Depth-2 traversal ids and order match the oracle | Stages 2 and 3 |
| Freshness and resolution visible | Stale or unresolved claims read as current | Core and MCP | Filters preserve every category | Mixed stale/current synthetic graph | Stages 1, 2, 4 |
| Publication coherent | Index and assertions from different states | Core integration | One immutable indexed snapshot per publish | Refresh failure keeps the previous snapshot | Stage 2 plus existing refresh tests |
| Memory stays local-friendly | Large repositories stop fitting | Observation against D8 | Index ≤ 10% of peak RSS | Budget exceeded → drop designator index | Stage 4 |
| MCP surface unchanged | Clients break | MCP integration | Same fields, ids, budgets, cursors | Budget exhaustion and pagination unchanged | Stage 3 |
| Java semantics unchanged | Faster indexing invents facts | Frontend fixture | ADR 004/008 facts identical | Out-of-scope, ambiguous, missing, provider removal | Stage 5 if implemented |
| No new external dependency | Local/offline guarantee weakens | Build review | No database in any lane | Nothing to miss, because nothing is required | Stage 6 |

## SQLite Position

SQLite stays a credible backend for a later persistence plan: cold-start
avoidance, memory-bounded very large repositories, multi-process reads. When that
happens, SQL tables store assertions and derived projections; they must never
decide semantic truth the graph cannot prove.

It is not the first move here. This plan proves the smaller contract — given one
immutable snapshot, identity and relationship lookups are indexed — which keeps
the win close to the measured pain, keeps every lane local and cheap, and leaves
a clean interface a SQLite-backed implementation can satisfy later.

## Definition Of Done

- `semidx_health`, `semidx_references`, and `semidx_context` no longer pay a
  linear unit or entity scan per assertion, and anchored relationship queries no
  longer scan the full assertion array.
- A deterministic work-bound test would fail under the old path.
- Ids, order, resolution, freshness, producer, evidence, and designator behavior
  are provably unchanged against a linear oracle.
- No MCP tool argument, schema field, or budget semantic changed.
- Index memory is measured against D8 and recorded.
- Follow-up 012 is closed or narrowed, and the progress log records final
  commands, results, residual risk, and commits.
