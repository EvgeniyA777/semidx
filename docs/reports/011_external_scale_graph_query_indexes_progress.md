---
title: "External-scale graph query indexes progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-18"
---

# 011: External-Scale Graph Query Indexes Progress

Companion log for
[docs/plans/011_external_scale_graph_query_indexes.md](../plans/011_external_scale_graph_query_indexes.md).

## Current Status

Stages 0 through 4 are complete. The cost model in the plan's
[Current Evidence](../plans/011_external_scale_graph_query_indexes.md#current-evidence)
is confirmed on a local synthetic graph, so the plan's stage order stands and its
Start Rule stop condition is not triggered. Identity lookups are now constant
time, anchored relationship queries read from a derived adjacency index instead
of scanning, and a committed test proves the bound at a size past the external
Java probe that motivated the plan. Nothing about graph semantics has changed:
no assertion was added or removed, and no claim's resolution, freshness,
producer, or evidence moved.

The open item carried forward is honest attribution, not code: Stage 1's product
latency on external Java scale was **not measured**, because no external
reproduction was available. See
[What This Stage Does Not Claim](#what-this-stage-does-not-claim).

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Baseline and harness | Completed | Synthetic graph committed at 5,045 assertions over 249 live units. Baseline confirms both costs: `countAssertions` examines 629,508 stored records to answer over 5,045 assertions, and an anchored query still walks all 5,045 candidates. |
| Stage 1: Constant-time identity lookups | Completed | Identity lookups read position tables built in `publish`. Work to answer `countAssertions` over the synthetic graph fell from 629,508 examined records to 5,044 — a factor of 124.8, which is half the live unit count, exactly what the cost model predicted. Results are unchanged against a linear reference over every id the graph issued. |
| Stage 2: Relationship adjacency index | Completed | Three derived indexes built in `publish`: outgoing and incoming as compressed sparse row, designators as a map. An anchored query now inspects exactly as many assertions as it returns — 5,045 candidates down to 4, and the depth-2 traversal 25,225 down to 16. Parity against the linear oracle is asserted on ids and order over 2,400 filter combinations. |
| Stage 3: MCP hot path parity | Completed | No MCP code needed changing: `semidx_references` and `semidx_context` already anchor every pass and never reach past `Snapshot.relationships`. Parity is proved by sending the same request down both access paths and comparing the responses byte for byte. |
| Stage 4: Deterministic scale proof | Completed | Inspected candidates equal returned answers for anchored queries and depth-2 traversal, asserted at three sizes up to 244,559 assertions — past the 230,753 measured on apache/dubbo. The same assertions fail under the restored full-scan path, in the same test. Index memory is 1.008× its computed expectation against D8's 2× ceiling. |
| Stage 5: Java write-path measurement | Not started | — |
| Stage 6: Documentation and closure | Not started | — |

## Plan Readiness Gate

Applied on 2026-09-18 before Stage 0, against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate).

**No hard fail. Execution proceeds.**

- Product behavior is explicit and does not conflict with `RULES.md`,
  `MEMORY.md`, the constitution, or the implementation: the plan changes how
  known assertions are found and states, as a scope boundary, that it adds no
  assertion, removes none, and changes no claim's resolution, freshness,
  producer, or evidence.
- Scope and non-scope are explicit and name what must not move: no MCP tool
  shape, no cursor or budget semantics, no `semantic_contract_version`, no
  database or persistence, no approximate fallback, no Java resolution rule
  change, no shared-core `module` or `IMPORTS`.
- The key technical decisions are recorded as decisions, not options: D1–D11
  fix authority, ownership, build time, data structure, anchor selection,
  post-filters, target/designator disjointness, the memory budget, the form of
  the scale proof, the write-path separation, and how Stage 1's and Stage 2's
  wins are attributed apart.
- Branches carry through. Stage 1 names what to do when an id exceeds the dense
  table; Stage 2 names what to do when ordering or ownership goes wrong;
  Stage 5 is conditional and its skip path ("record that and change no code") is
  a stated valid outcome with its own verification.
- Stages do not depend on later outcomes. Stage 0 produces the harness every
  later stage measures against, and the plan's Start Rule carries an explicit
  stop condition: re-open the plan if Stage 0 measurement contradicts the cost
  model.
- DoD is observable: parity against a linear oracle, a work-bound assertion that
  must fail under the pre-Stage-2 path, a computed memory expectation, and named
  commands that exist in this repository.

One executor decision the plan leaves open is recorded here.

**The work counters arrive in Stage 0, not Stage 4.** Stage 4 requires a
test-only inspected-candidate counter on the iterator; Stage 0 requires baseline
*inspected-work counts* for `countAssertions`, which uses no iterator. A baseline
cannot be recorded with an instrument that does not exist yet, so the counters
are built in Stage 0 as part of the harness and Stage 4 adds the assertion that
would fail under the old path. Two counters exist rather than one, because the
plan's two costs must not be conflated in the record: `identity_records` counts
stored unit and entity records examined answering identity lookups (Cost 1), and
`candidates` counts assertions a relationship iterator examined (Cost 2).

## Stage 0: Baseline And Harness

### Environment

| Fact | Value |
| --- | --- |
| Date | 2026-09-18 |
| Toolchain | `./scripts/check-zig-version.sh` — Zig 0.16.0 matches semidx target |
| Branch | `dev` |
| Commit before first change | `67f5774` |
| Worktree before first change | clean |

### Work

- `src/core/scale_test.zig`: a synthetic graph builder and the baseline
  measurement over it. Parameterised by unit count, definitions per unit, and
  noise per unit; it produces one focus entity with a known neighbourhood
  (4 outgoing, 4 incoming, 12 at depth 2), noise relationships that never touch
  that neighbourhood, unresolved designator relationships including one
  designator several units share, units edited after analysis so their claims are
  stale beside current ones, and units removed after analysis so entity ids and
  published positions diverge. It is local, deterministic, and committed.
- `src/core/graph.zig`: test-only work counters (`graph.work`). Outside a test
  build every call compiles away.
- `src/core/root.zig`: the synthetic file joins the core test block only, so it
  is not part of the core's API.

### Baseline

Default synthetic size: 256 units requested, **249 live**, 2,740 entities,
**5,045 assertions**. Measured on `zig build test-core`, Zig 0.16.0, debug.

| Query | Answers | Identity records examined | Candidates inspected |
| --- | --- | --- | --- |
| `countAssertions` (default freshness) | 4,905 | 629,508 | 0 |
| `relationships` anchored on `source` | 4 | 629,508 | 5,045 |
| `relationships` anchored on `target` | 4 | 629,508 | 5,045 |
| Depth-2 traversal from the focus entity | 16 | 3,147,540 | 25,225 |

### Cost Model Check

The plan's Start Rule requires stopping if this measurement contradicts the cost
model. It does not; it reproduces it.

- **Cost 1 is real and dominates.** `countAssertions` walks no relationships and
  still examines 629,508 stored records to answer over 5,045 assertions —
  about 125 per assertion, which is half of 249 live units, exactly the average
  cost of a linear `Snapshot.unit` scan. This is the term that explains
  `semidx_health` on the Plan 010 probe, and no adjacency index can touch it.
- **Cost 2 is real and independent.** An anchored query returning **4** answers
  inspects all **5,045** candidates. The anchor is applied inside the loop, so it
  narrows the answer and not the work.
- **They multiply, as predicted.** The depth-2 traversal issues 5 anchored
  queries (the focus plus its 4 callees) and pays 5 × 5,045 candidates and
  5 × 629,508 identity records. `frontier × assertions × units`, not
  `frontier × assertions`.

The stage order in the plan follows from this, and it holds: Cost 1 is the
larger term here by a factor of about 125, and it is the cheaper fix.

### Deviations From The Plan Text

**No wall clock is recorded from the core harness.** Zig 0.16.0 removed
`std.time.Timer`; timing now requires an `std.Io` instance, which a parser-free
core test lane has no other use for. D9 already makes the deterministic work
count the claim and leaves wall clock an observation, so the harness records
work counts only. Latency observations belong where a user feels them — the MCP
hot path — and are recorded in later stages.

**No external reproduction was run.** The plan marks it optional and never a
gate.

### Named Commands

- `zig build test-core` runs the synthetic graph and its assertions.
- To print the measurement table, set `print_measurements = true` in
  `src/core/scale_test.zig` and re-run `zig build test-core`. It is off in the
  committed lane so that a lane that prints on every run does not make other
  failures harder to read.

### Verification

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches semidx target |
| `zig fmt --check build.zig src tests` | clean |
| `zig build test-core` | 91/91 tests passed (67 core, 24 source) |

## Stage 1: Constant-Time Identity Lookups

### Work

- `src/core/graph.zig`: `publish` builds `entity_positions` and `unit_positions`
  — dense `[]u32` indexed by `id.index()`, holding the position in the published
  slice, with `absent_position` for an id the snapshot does not hold. Tables are
  sized by the highest live id, so a graph started after another pays for its
  reserved-id gap once here rather than on every query. `Snapshot.unit`,
  `Snapshot.entityById`, and `Snapshot.unitAnalysis` read them; signatures,
  return types, and null behavior are unchanged. `Snapshot.deinit` frees them
  like every other snapshot slice.
- `src/core/scale_test.zig`: parity against a linear reference, and a cost
  assertion.

`unitByPath` and `findEntity` were left alone, per the plan: they are not on the
per-assertion path.

An id above the highest live id is absent by being past the end of the table.
There is no fallback scan, deliberately — a scan here is the defect the stage
removes, and reintroducing one under a branch name would hide it rather than
fix it.

### Result

Same synthetic graph: 249 live units, 2,740 entities, 5,045 assertions.

| Query | Answers | Identity records before | After | Factor |
| --- | --- | --- | --- | --- |
| `countAssertions` (default freshness) | 4,905 | 629,508 | 5,044 | 124.8× |
| `relationships` anchored on `source` | 4 | 629,508 | 5,044 | 124.8× |
| `relationships` anchored on `target` | 4 | 629,508 | 5,044 | 124.8× |
| Depth-2 traversal from the focus entity | 16 | 3,147,540 | 25,220 | 124.8× |

Answers are identical in every row. The factor is 124.8 in every row, and that
is the confirmation rather than a coincidence: it is half of 249 live units, the
average cost of the linear scan this stage removed. The cost model predicted
`units / 2`, and that is what was measured.

Candidate counts are untouched by this stage — an anchored query still inspects
all 5,045 assertions, because the anchor is still applied inside the loop. That
is Stage 2's term, and keeping it visibly unchanged here is what lets the two
wins be attributed apart, per D11.

### What This Stage Does Not Claim

**No product latency number is claimed for Stage 1.** D11 predicts that removing
this term alone probably makes the Plan 010 probe interactive, and the measured
factor of 124.8 on a 249-unit graph is consistent with the ~2,000× predicted on
Dubbo's 4,050 units. But consistent is not measured: no external reproduction
was run, so `semidx_health`, `semidx_references`, and `semidx_context` at
`depth=2` have no post-Stage-1 wall clock recorded against Plan 010's numbers.

The plan is explicit that this measurement cannot be taken later without
conflating Stage 1's win with Stage 2's. It is therefore recorded as **not
taken**, not as inferred. What Stage 1 proved is the work bound and the parity;
the product claim on external Java scale remains open and is the honest gap in
this record.

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | clean |
| `zig build test-core` | 93/93 tests passed |
| `zig build test` | 228/229 passed, 1 skipped (pre-existing dogfood skip; no repository root outside `zig build dogfood`) |

No test expectation was changed. Two tests were added.

## Stage 2: Relationship Adjacency Index

### Work

- `src/core/relationship_index.zig`: a new module owning three derived indexes
  over one published assertion array — outgoing by source entity, incoming by
  entity target, and a designator map. The two entity indexes are compressed
  sparse row: one allocation each, built by counting per key and then filling
  forward over the assertion array, so bucket contents come out in snapshot
  order by construction rather than by a sort. It owns its own `deinit` and
  reports its own `byteSize`.
- `src/core/graph.zig`: `publish` builds the index after the assertion array is
  in its final order. `Snapshot.relationships` chooses candidates and
  `RelationshipIterator` walks either a chosen position list or the whole array.
  `countRelationships` and `firstRelationship` were not touched; they call
  `relationships` and inherited the path.
- `src/core/scale_test.zig`: parity against the oracle, an absent-anchor proof,
  and a coherent-publication test.

### One Decision The Plan Did Not Settle

**The entity indexes are keyed by entity id, not by entity position.** D4 says
position, and position would be the smaller table. It is also wrong here, and
the difference is a correctness one rather than a tuning one.

A snapshot can hold a relationship whose target entity is no longer live:
`checkAssertions` deliberately admits a stale claim that reached into another
unit whose provider removed the definition. That entity has no position, because
`publish` copies only live entities. Keying the incoming index by position would
give that claim no key, and a query anchored on that target id — which the linear
path answered by comparing ids, never liveness — would silently return nothing.
Faster, and wrong in exactly the direction this plan forbids.

Keying by id costs a table sized by the highest id any live entity or any
assertion names, rather than by the live entity count. D8's expected-bytes
formula is adjusted accordingly in Stage 4's measurement, and the adjustment is
recorded there rather than applied quietly.

### Result

Same synthetic graph: 249 live units, 2,740 entities, 5,045 assertions.

| Query | Answers | Candidates before | After | Factor |
| --- | --- | --- | --- | --- |
| `relationships` anchored on `source` | 4 | 5,045 | 4 | 1,261× |
| `relationships` anchored on `target` | 4 | 5,045 | 4 | 1,261× |
| Depth-2 traversal from the focus entity | 16 | 25,225 | 16 | 1,577× |

An anchored query now inspects exactly as many assertions as it returns. That is
not a coincidence of this fixture: the candidate list *is* the answer set before
post-filters, so inspected work follows the neighbourhood and stops following
the repository.

`countAssertions` is unchanged at 0 candidates and 5,044 identity records. It
walks no relationships, so no adjacency index can help it, and none did. That is
the check that the two stages' wins are not being credited to each other.

### Parity

The oracle is the pre-index filter loop, written out in full rather than sharing
code with the implementation — a parity test that shares the logic it checks
proves only that the logic equals itself.

The matrix is 20 anchors × 5 kinds × reference-query on and off × 4 resolutions
× 3 freshness settings = 2,400 comparisons per snapshot, each on assertion
**ids and order**, not counts. The anchors include: no anchor; both directions
on entities that have relationships in one direction only; both anchors at once,
so the shorter list is chosen and the other anchor still has to be applied; a
removed entity id and an id never issued; a designator several units share, one
from a unit edited afterwards, one from a unit that left the index, and one
nothing ever recorded; and entity-plus-designator combinations that must stay
empty because a target is one or the other and never both.

### Coherent Publication

A snapshot published before an edit keeps answering its own assertions after a
later publication, and the later snapshot's index describes the later
assertions. Both are re-checked against the oracle in the same test, so a mixed
state would have to agree with a full scan of a state that does not exist.

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | clean |
| `zig build test-core` | 96/96 tests passed |
| `zig build test` | 231/232 passed, 1 skipped (pre-existing dogfood skip) |
| `zig build test-mcp` | 28/29 passed, 1 skipped |

No test expectation was changed anywhere, including in the MCP lane.

## Stage 3: MCP Hot Path Parity

### Work

**No MCP code changed, and that is the finding rather than a shortcut.**
`semidx_references` already anchors its two passes on `target` and `source`, and
`semidx_context` already anchors every focus pass and every traversal step
through the same `relationshipPasses` helper. All three relationship call sites
in `src/mcp/tools.zig` go through `Snapshot.relationships`; nothing in the MCP
layer reaches past it into the assertion array. The hot path therefore inherited
Stage 2 without an edit, which is what a boundary is for.

- `src/mcp/root.zig`: one test.
- `src/core/graph.zig`: `bypass_relationship_index`, a test-only switch that
  sends relationship queries back down the full-scan path. The branch reading it
  is guarded by `builtin.is_test`, so it compiles away outside a test build.

### How Parity Is Proved

A hand-written oracle shows that two implementations agree with the oracle. The
switch above allows something stronger: send the *same request* down both access
paths and compare what comes back, **byte for byte**. That covers far more than
relationship ids and their order — the same fields, the same de-duplication, the
same traversal rendering, the same budget outcome, the same hints.

Three calls are compared this way, over a fixture with a call cycle and a
repeated neighbour so that an entity is reached from two ends:
`semidx_context` at `depth=2` with `direction=both`, `semidx_context` at
`depth=3` with `direction=outgoing`, and `semidx_references` with
`direction=both`. Each comparison also asserts that the indexed run inspected
strictly fewer candidates than the scanned run, so a byte-identical result can
never come from both runs taking the same path.

### Teeth

The parity tests were checked by breaking the implementation on purpose: filling
the compressed sparse rows backwards over the assertion array, which is the
exact defect D4's build order exists to prevent. Three tests failed — the core
parity test, the coherent-publication test, and this MCP byte-for-byte test. The
change was then reverted. A parity test that has never failed is a hypothesis.

### Latency Observed On This Repository

From `zig build preview-gate`, over a copy of this repository, after the change:

| Call | Time | Bytes |
| --- | --- | --- |
| `semidx_references writeString` (limit 1000) | 0 ms | 27,968 |
| `semidx_context writeString incoming depth 2` | 1 ms | 66,996 |
| `semidx_context health` (relationship_limit 500) | 1 ms | 61,472 |
| `semidx_refresh` after a one-file edit | 22 ms | 1,213 |

These are observations, not gates, and this corpus is about 5,500 assertions —
three orders of magnitude below the probe that motivated the plan. They say the
hot path is not slow here; they cannot say what happens at Java scale. That
question is answered by the work bound in Stage 4, not by these numbers.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-mcp` | 29/30 passed, 1 skipped |
| `zig build test` | 233/235 passed, 2 skipped |
| `zig fmt --check build.zig src tests` | clean |

No expectation changed. Tool schemas, field order, de-duplication, traversal
rendering, cursors, budgets, and `semantic_contract_version` are untouched, and
no tool argument was added.

## Stage 4: Deterministic Scale Proof

### Work

- `src/core/scale_test.zig`: the work-bound proof at two default sizes, the same
  proof at external scale, and the index memory check.

### The Bound

For an anchored query and for a depth-2 traversal, **inspected candidates equal
returned answers**. Not "fewer", not "proportional": exact, because the
synthetic graph's answers are exact and the candidate list is the answer set
before post-filters.

The same assertions are then re-run with `bypass_relationship_index` set, which
restores the access path this plan replaced. There the anchored query inspects
every assertion in the snapshot, and the depth-2 traversal inspects every
assertion **once per frontier step** — `assertions × (1 + fan_out)`. Both are
asserted exactly. The bound is therefore not a number with no claim attached: it
is a bound the old path provably breaks, in the same test, on the same graph.

| Size | Live units | Entities | Assertions | Anchored candidates | Depth-2 candidates |
| --- | --- | --- | --- | --- | --- |
| default | 249 | 2,740 | 5,045 | 4 | 16 |
| external | 12,110 | 133,211 | 244,559 | 4 | 16 |

The graph grows by a factor of about 48 in assertions between these two rows and
the bound does not move. The proof also runs at a third, smaller size (64 units)
whose counts are asserted but not recorded here; three sizes rather than one is
what makes this a bound rather than a coincidence.

Under `bypass_relationship_index`, the depth-2 traversal at the default size
inspects 25,225 candidates and at external scale 1,222,795 — `assertions ×
(1 + fan_out)` in both cases, asserted exactly.

### External Scale

`external_scale` builds 12,500 units and publishes **244,559 assertions**, past
the 230,753 measured on apache/dubbo in Plan 010 — which is the size the plan
asks Stage 2 to be accepted at. The test asserts that count, so the claim cannot
quietly stop being true if the builder's shape changes.

It is skipped in a debug build and runs outside one. Debug is what makes this
size impractical, not the size itself, and the default lane has to stay quick
enough that agents keep running it. The acceptance claim was not lowered to fit
the default lane; it was moved to the lane that can carry it.

**Named command:** `zig build test-core -Doptimize=ReleaseFast`.

### Memory Against D8

| Fact | Value |
| --- | --- |
| Expected index bytes, from the fixture's actual counts | 2,620,054 |
| Measured index bytes | 2,642,004 |
| Ratio | 1.008× |
| D8's ceiling | 2× |
| Peak RSS of the test process at that size | 543 MB |
| Index as a share of peak | ~0.5% |

D8's expected-bytes formula is adjusted for the Stage 2 decision to key the
entity indexes by entity id rather than entity position: the two offset arrays
are `4 × (key space + 1)` rather than `4 × (entities + 1)`, where the key space
is the highest id any live entity or any assertion names. Nothing else in the
formula changes, and the measured value is computed by the index reporting its
own size rather than by inference.

The ratio being 1.008 rather than, say, 1.7 is itself worth recording: it says
there is no per-key allocation hiding anywhere, which is the failure D4 exists
to prevent and the reason a percentage-of-RSS ceiling was rejected. At 10% of
this run's peak the ceiling would have been 54 MB — twenty times what the
structure needs, and unable to fail.

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core` | 97/98 passed, 1 skipped (the external-scale proof, skipped in debug by design) |
| `zig build test-core -Doptimize=ReleaseFast` | 98/98 passed, 873 ms, peak RSS 543 MB |
| `zig build test` | 233/235 passed, 2 skipped |
| `zig build preview-gate` | success, 14/14 steps, 6/6 tests passed |
| `zig fmt --check build.zig src tests` | clean |

`preview-gate` prints `failed command:` lines during the dogfood recovery
scenario. Those are its deliberate allocation-failure injections, not failures:
the step reports success and the build exits 0.
