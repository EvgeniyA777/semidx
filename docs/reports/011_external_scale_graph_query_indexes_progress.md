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

Stage 0 is complete. The cost model in the plan's
[Current Evidence](../plans/011_external_scale_graph_query_indexes.md#current-evidence)
is confirmed on a local synthetic graph, so the plan's stage order stands and
its Start Rule stop condition is not triggered. Nothing about graph semantics has
changed.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Baseline and harness | Completed | Synthetic graph committed at 5,045 assertions over 249 live units. Baseline confirms both costs: `countAssertions` examines 629,508 stored records to answer over 5,045 assertions, and an anchored query still walks all 5,045 candidates. |
| Stage 1: Constant-time identity lookups | Not started | — |
| Stage 2: Relationship adjacency index | Not started | — |
| Stage 3: MCP hot path parity | Not started | — |
| Stage 4: Deterministic scale proof | Not started | — |
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
