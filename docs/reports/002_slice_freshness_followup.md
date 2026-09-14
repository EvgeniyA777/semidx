---
title: "Slice freshness follow-up"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-13"
---

# 002: Slice Freshness Follow-up

A review of the first vertical slice
([plan 001](../plans/001_zig_vertical_slice.md),
[log 001](001_zig_vertical_slice_progress.md)) found three defects in what that
slice delivered. This log records the fixes.

## Findings And Disposition

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | High | After a failed reanalysis, the unit's earlier assertions stayed queryable as current graph facts. `Index.applyEdit` replaced the unit's contents, then `reconcile.integrate` returned early on a blocking diagnostic without withdrawing or marking anything, and snapshot queries returned the old facts normally. | Fixed. Freshness is now a first-class axis; see below. |
| 2 | Medium | The source container's evidence was stale after a successful edit. `setSourceUnitBytes` swapped the bytes only, so the `file` entity and the repository-to-file ingestion assertion kept the extent computed when the unit was first registered. | Fixed. Ingestion re-establishes what it claims about a unit whenever the contents change. |
| 3 | Low | `Parser.parse` accepted a previous tree, and an adapter test reused one across changed source without `ts_tree_edit`. Not a runtime bug — the analyzer passed `null` — but the API invited the mistake. | Fixed by removing the parameter. |

All three were accepted. None was deferred.

## Finding 1: Freshness

The defect was not that the old assertions were retained. Withdrawing them would
assert an absence nothing observed, and would destroy the identities a later
successful analysis needs in order to preserve them. The defect was that they
were retained *and presented as current*, with nothing telling a consumer that
the source they describe is gone.

Freshness is therefore modelled as its own axis, separate from resolution:

- `model.Freshness` is `current` or `stale`. A fully resolved fact about source
  that has since changed is still a fact about what its producer read, and it is
  still not current; an unresolved assertion about the contents on disk right
  now is current and still unresolved. Collapsing the two would lose information
  in both directions, and would make "we could not re-read this file"
  indistinguishable from "we read it and resolved nothing" — which
  [CONFORMANCE.md](../../CONFORMANCE.md) requires to stay distinguishable.
- Each source unit records `content_revision` (when its contents were
  established) and `analysis_revision` (when a frontend last analyzed it
  successfully). `UnitAnalysis` derives `pending`, `current`, or `stale` from
  the pair, and a `Snapshot` exposes it per unit.
- A claim observed in a unit is current when it was recorded at or after that
  unit's `content_revision`. One rule, applied to entities through a new
  `Entity.observed_revision` and to assertions through the revision they already
  carried. Nothing is special-cased by producer.
- `Index.applyEdit` now performs the edit in its own revision before analysis
  runs. That is what makes the rule work: ingestion establishes the new contents
  and thereby marks the unit's existing analysis stale, and analysis then either
  makes it current again or leaves it stale.
- Snapshot queries take `freshness`, defaulting to `.current`. A caller who did
  not ask for stale claims is never handed one. Stale claims remain in
  `snapshot.assertions` and `snapshot.entities` and are reachable by asking
  (`.freshness = .stale`, or `null` for either), so this is distinguishability,
  not concealment.
- `reconcile.integrate` calls `Graph.markAnalyzed` only on a successful pass,
  and withdraws the previous attempt's diagnostics on every pass, so diagnostics
  always describe the latest attempt rather than accumulating.

One related change fell out of it. `Graph.addEntity` no longer records an
existence assertion as a side effect; the producer that observed the entity
records it, with its own provenance and resolution. Allocating an entity and
claiming it exists are different acts, and only the second is an assertion.

## Finding 2: Source Container Extent

`setSourceUnitBytes` now refreshes the `file` entity's evidence and re-records
both ingestion claims about the unit — that the container exists, and that the
indexed source tree contains it — against the new extent. The `file` entity
keeps its id: its extent is a projection, and a projection moving is not an
identity change.

This also makes ingestion's claims about a stale unit correctly *current*:
ingestion did read the new contents, even when no frontend could analyze them.

## Finding 3: Previous-Tree API

`Parser.parse` no longer takes a previous tree. tree-sitter can reuse one only
if it has been told through `ts_tree_edit` exactly which byte ranges changed;
handing it an unedited tree makes it conclude the text is unchanged and return
the old parse. Nothing upstream tracks edit ranges, so the parameter could only
ever be misused. The replaced test now asserts the property that reuse would
have broken: two parses of different contents through one parser describe their
own contents.

`contract.PreviousParse` stays as the contract-level marker for an adapter that
does track edits.

## Changed Files

- `src/core/model.zig`, `src/core/graph.zig`, `src/core/reconcile.zig`
- `src/frontend/tree_sitter.zig`, `src/frontends/root.zig`
- `src/root.zig`, `src/main.zig`
- `tests/vertical_slice_test.zig`
- `fixtures/vertical-slice/java/edits/05_unparsable.java`
- `fixtures/vertical-slice/clojure/edits/05_unparsable.clj`
- `GLOSSARY.md`, `MEMORY.md`, `CONFORMANCE.md`
- `docs/reports/002_slice_freshness_followup.md`

## Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 37/37 passed, up from 32. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 37/37 passed; the core still builds and is tested with no parser input. |
| `zig build test --summary all` | 66/66 passed, up from 58: core 37, adapter 6, frontends 6, fixture and edit-history 17. |
| `zig build run -- fixtures/vertical-slice/java/Greeter.java fixtures/vertical-slice/clojure/greeter.clj` | Both units reported `current`, 0 stale assertions. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

New tests, each of which fails against the previous implementation:

- **core** — an edit whose analysis fails stops answering current-state queries:
  the unit reports `stale`, the definitions and relationships disappear from
  default queries, they are still reachable as stale, the entities still exist
  so identity survives, and ingestion's claims about the unit are current.
- **core** — a stale unit becomes current again with identity preserved across
  the gap: after a failed analysis and a repair, all entities are `preserved`,
  none created or lost, and the failed attempt's diagnostic is gone.
- **core** — failed analysis of unchanged contents leaves the unit current. This
  is the boundary case: a failure is only a staleness event when the contents
  actually moved.
- **core** — one unit going stale does not make another unit stale.
- **core** — a unit is pending until analyzed and current afterwards.
- **core** — the source container's extent follows an edit, for both the `file`
  entity and the ingestion containment assertion.
- **fixture** — editing the Java fixture into unparsable source stops its facts
  being current, leaves the Clojure unit untouched, and restores the same entity
  ids when the source is repaired.
- **fixture** — the same for the Clojure fixture, checking that the stale
  definition is still reachable by id.
- **fixture** — the source container's extent tracks the file it stands for.
- **adapter** — one parser parses successive contents independently.

## Residual Risk

- **Freshness is per unit, not per claim's dependencies.** A cross-unit
  assertion would be current while the unit it points into is stale. The slice
  has no cross-unit assertions, so nothing exercises this; repository-scale
  ingestion must decide how an edit invalidates claims in *other* units before
  it adds any.
- **Stale claims accumulate.** Nothing ever withdraws them, so a unit that stays
  unparsable keeps its old assertions in memory indefinitely. Bounded here by
  the slice being in-memory and small; a long-lived process needs a policy.
- **Default-current is a query default, not an enforced boundary.** A consumer
  walking `snapshot.assertions` or `snapshot.entities` directly sees everything
  and must consult `assertionFreshness` or `entityFreshness` itself. The arrays
  are documented as raw, but the type does not prevent the mistake.
- Everything in log 001's Residual Risk section still stands.

## Next Handoff

Unchanged from log 001, with one ordering note: the freshness semantics settled
here are a precondition for repository-scale ingestion, because that is where
cross-unit invalidation first becomes possible. `CORE.md` candidate admission is
still independent of both.
