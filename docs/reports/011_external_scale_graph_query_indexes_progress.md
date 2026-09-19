---
title: "External-scale graph query indexes progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-18"
---

# 011: External-Scale Graph Query Indexes Progress

Companion log for
[docs/plans/011_external_scale_graph_query_indexes.md](../plans/011_external_scale_graph_query_indexes.md).

## Current Status

**Plan 011 is complete.** The cost model in the plan's
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
| Stage 5: Java write-path measurement | Completed | No code changed, which the plan names a valid outcome. On 600- and 1,200-unit Java corpora every write-path term is linear in units, a one-file-edit refresh costs 13 ms and is indistinguishable from one that analyzes nothing, and the units reanalyzed when a package's exports change is constant at 41. |
| Stage 6: Documentation and closure | Completed | `MEMORY.md` states the indexed access path as current reality, Follow-up 012 is closed against Plan 011 with its two deliberate departures recorded, and the plan is marked executed. |

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

## Stage 5: Java Write-Path Measurement

### Outcome

**No code changed.** The plan names this a valid and expected outcome, and the
measurements support it: every write-path term is linear in units or constant,
and Java binding work is not the largest term in the refresh a user pays on
every edit.

### Method

Two synthetic Java corpora, 600 and 1,200 files, 20 classes per package, each
class carrying a single-type import of a class in another package so that import
binding has to look outside the unit's own package. Driven through the real
stdio server (`zig-out/bin/semidx-mcp`, ReleaseFast), one process per run, best
of five runs, warm filesystem cache. The corpora are throwaway and live outside
the repository: no external repository is committed and none is a conformance
target.

### Measurements

| Measurement | 600 units | 1,200 units | Growth for 2× units |
| --- | --- | --- | --- |
| Cold `--root` index, to first answered call | 33.6 ms | 66.9 ms | **1.99×** |
| `semidx_health`, warm | 0.15 ms | 0.25 ms | 1.67× |
| `semidx_refresh`, nothing changed | 6.49 ms | 13.95 ms | 2.15× |
| `semidx_refresh` after editing one file | 6.16 ms | 13.29 ms | 2.16× |
| `semidx_refresh` after a class appears in a package | 7.06 ms | 13.61 ms | 1.93× |
| Units reanalyzed when a package's exports change | **41** | **41** | **1.00×** |

### The Two Terms, Measured Apart

Plan 010's Stage 4 introduced two costs, and the plan is explicit that reporting
one number for both is how the wrong fix gets chosen.

**Per-unit binding lookup — not the dominant term, and not visible in refresh.**
A refresh that analyzes one edited unit costs 13.29 ms at 1,200 units; a refresh
that analyzes *nothing* costs 13.95 ms. The edit adds nothing measurable. What
the refresh actually pays for is walking the tree and comparing content ids for
every unit, which is inherent to a scan-based refresh with no file watching, and
which the plan puts out of scope. A Java-side candidate projection would
therefore optimize a term that is already below the noise of the term beside it.

**Extra reanalysis passes — bounded, and constant in repository size.** When a
class appears in a package, 41 units are reanalyzed: the package's 20 classes,
the 20 importers of that package, and the new unit. That number is **identical**
at 600 and 1,200 units. The importer hint widens what a package change
invalidates, exactly as Plan 010 recorded, but it widens it by package size and
importer count — not by repository size. That is the shape the plan predicted in
D10, now measured rather than assumed.

### Against The Plan's Criteria

| Criterion | Threshold | Measured | Act? |
| --- | --- | --- | --- |
| `semidx_refresh` after editing one file | above ~1 s, or Java binding work is its largest term | 13.3 ms, and Java binding work is not measurable in it | No |
| Cold `--root` index time | only if super-linear in units | 1.99× for 2× units | No |
| Growth shape across two sizes | any term growing faster than linear | every term linear or constant | No |

### What This Does Not Say

These corpora are 1,200 small files. Plan 010's probe was 4,050 real Java units
and its cold index cost 17.5 s, about 5 ms per unit, against 0.056 ms per unit
here. That gap is file size and real Java complexity, not access-path shape, so
what transfers from this measurement is the **growth shape** — linear in units,
constant in repository size for the reanalysis term — and not the constants.

**Plan 010's 17.5 s → 21.5 s ingestion regression was not re-measured.** Doing so
needs the external repository, which the plan keeps optional and out of
conformance. The decision to change no code rests on the growth shape and on
binding work being immeasurable inside refresh, not on a claim that the
regression is gone.

### Verification

No code changed, so Stage 4's command set stands unchanged and was re-run in
Stage 6.

## Stage 6: Documentation And Closure

### Work

- `MEMORY.md`: the indexed access path is stated as current implementation
  reality beside the snapshot bullet, not as a changelog entry; the external-scale
  latency risk is replaced by what is actually still unknown; Plan 011's outcome
  and the Java write-path measurement join the near-term priorities; the report
  joins the evidence pointers; the named ReleaseFast command joins the command
  list. The settled ADR 007 text-fallback block was compressed into its ADR to
  stay inside the document's own 350-line bound.
- `docs/followups/012_external_scale_query_latency.md`: **closed**, with both
  departures from its acceptance direction recorded in it rather than left to be
  noticed — the latency gate became a work bound, and the Java write-path work
  was measured and declined.
- `docs/followups/README.md`: 012 moves from open to completed.
- `docs/plans/011_external_scale_graph_query_indexes.md`: marked executed.
- This log: marked completed.

`docs/mcp/habit_loop_gate.md` was **not** changed. The scale proof adds no gate
command and changes no gate expectation: `zig build preview-gate` runs exactly
what it ran before and its hard gates are untouched. The named command the plan
asked to be documented is a test lane variant, so it is recorded in `MEMORY.md`'s
command list and in Stage 4 above, where an agent would look for it.

### Drift Control

| Owner | State |
| --- | --- |
| `ARCHITECTURE_CONSTITUTION.md` | Untouched and not in tension. §1 and §3 hold because every index is a projection whose answers are read from assertions; §5 holds because indexes are built per published state and never mutated afterwards; §7 holds because no MCP shape changed; §8 holds because nothing was added to any build or lane. |
| `SPEC.md`, `CORE.md` | Unchanged. No core kind, contract, schema field, or `semantic_contract_version` moved. |
| `CONFORMANCE.md` | Unchanged. The work bound is a core test, not a new scenario family. |
| `GLOSSARY.md` | Unchanged. No durable vocabulary was introduced: "adjacency index" and "position table" are implementation structures owned by `src/core/relationship_index.zig` and `src/core/graph.zig`. |
| ADRs | None needed. No new dependency, no changed architectural answer — this is an access path behind an unchanged API, and constitution §11's questions are answered the same way they were before it. |
| `MEMORY.md`, follow-ups | Updated above. |

### Residual Risk

1. **Product latency at external Java scale is unproven.** Stage 1's and
   Stage 2's wins are proven as work bounds, at a synthetic size past the probe.
   No post-change wall clock was taken on apache/dubbo, and the plan is explicit
   that the Stage 1 measurement in particular cannot be taken later without
   conflating the two stages. Re-running the Plan 010 probe is the cheapest
   closure and is recorded in `MEMORY.md` as the next step.
2. **The entity index key space follows ids, not live entity count.** A long
   session with heavy churn makes both the position tables and the two offset
   arrays grow with the highest id issued rather than with what is live. Nothing
   reclaims ids while the graph lives, which `MEMORY.md` already records as a
   known risk. At 244,559 assertions the whole index is 2.6 MB, so this is a
   shape to watch, not a present cost.
3. **Two test-only globals now exist in the core** — the work counters and
   `bypass_relationship_index`. Both compile away outside a test build, and both
   are process-wide rather than per-snapshot, so a future parallel test runner
   would need them scoped.
4. **The write-path decision rests on synthetic Java.** 1,200 small files are
   not 4,050 real ones. What transfers is the growth shape, not the constants.

### Verification

Run after the last code change, on `dev`, Zig 0.16.0.

| Command | Result |
| --- | --- |
| `./scripts/check-zig-version.sh` | Zig 0.16.0 matches semidx target |
| `zig fmt --check build.zig src tests` | clean |
| `zig build test-core` | 97/98 passed, 1 skipped (external-scale proof, by design in debug) |
| `zig build test-core -Doptimize=ReleaseFast` | 98/98 passed |
| `zig build test` | 233/235 passed, 2 skipped |
| `zig build test-mcp` | 29/30 passed, 1 skipped |
| `zig build dogfood` | success |
| `zig build preview-gate` | success, 14/14 steps, 6/6 tests passed |

### Commits

| Stage | Commit |
| --- | --- |
| Stage 0 | `54adcb4` |
| Stage 1 | `b593633` |
| Stage 2 | `97f541a` |
| Stages 3 and 4 | `df6287c` |
| Stages 5 and 6 | this commit |
