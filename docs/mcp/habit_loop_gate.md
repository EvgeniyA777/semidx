---
title: "Habit loop gate"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-27"
---

# Habit Loop Gate

The local preview's habit-loop gate: one command that drives the built
`semidx-mcp` through the agent [habit loop](../../GLOSSARY.md) over stdio, on
more than one root, and fails when the loop stops being useful or honest.

```sh
zig build preview-gate --summary all
```

It is one command inside a release gate, not the whole release gate, and not a
release: running it cuts no tag, publishes nothing, and publishes no semantic
contract. `semantic_contract_version` is `null` in every result it checks.
What it proves is current preview behavior, described in
[Local MCP preview](local_preview.md); it is not a stable interface. This
document owns the terms *hard gate*, *observation*, and *gate profile* as used
for the gate.

## Operation

- Prerequisites are the ones `zig build` already needs: Zig 0.16.0, pinned
  grammar sources, and a local tree-sitter runtime. After those are installed
  the gate uses no network, no service, and no hosted client.
- Every profile works in a temporary directory. The gate never edits the
  repository or `fixtures/`.
- Every response and every exit is awaited for at most 30 seconds. On expiry the
  server is killed and the gate fails naming what it awaited and printing the
  server's stderr. This is a hang bound, not a latency claim.
- The step always runs: the repository and fixtures are read at run time, so no
  build cache can skip it.
- A hard-gate failure prints `gate: FAIL [<profile>] <gate>: <detail>` before
  the test fails. A passing profile prints its evidence summary (see
  [Evidence Summary](#evidence-summary)).

## Profiles

| Profile | Root | Why |
| --- | --- | --- |
| `repository-copy` | Every source unit a scan of this repository finds, copied byte for byte into a temporary directory. | Realistic source: the size, shape, and diagnostics an agent working on semidx sees. Also runs the evidence-text opt-in proof and the refresh failure-injection recovery proof. |
| `fixture` | A few files from `fixtures/vertical-slice` copied into a temporary directory, plus one file no frontend indexes. | Controlled degradation: known facts, unresolved calls, unsupported constructs, a unit that fails analysis, a unit that becomes stale, and a file outside every frontend's coverage. Fast, and independent of how this repository grows. |
| `sync-trust` | The nine synthetic units `fixtures/working_copy_sync/units/` froze ([Plan 016](../plans/016_trustworthy_working_copy_sync.md) Stage 0), copied into a temporary directory. | The ADR 014 trust contract end to end: a branch-switch-shaped batch (one unit changed, one removed, one added) applied from outside the server, a graph read that must fail closed before syncing, a sync that publishes the batch in one pass, corrected data after sync, a cursor issued before the sync failing after the revision changes, and a scan failure once the root disappears. Independent of `fixtures/vertical-slice` and of this repository's own size. |

`zig build dogfood` runs the `repository-copy` profile alone. `preview-gate`
runs all three profiles and is the canonical gate.

## Required Call Sequence

Each profile makes these calls, in this order, over one server process:

1. `semidx_sync`, as the very first call
2. `semidx_health`
3. `semidx_outline`
4. `semidx_repo_map` at the default compact detail
5. `semidx_find_definitions`
6. `semidx_references`
7. `semidx_context`
8. an edit of a file in the temporary root
9. `semidx_refresh`
10. a lookup or context call after the refresh

A profile may make further calls between these (full-detail comparisons,
bounded list probes). A profile that skips a required call fails the
`call_sequence` gate.

## Hard Gates

Every hard gate fails the profile. Names are the ones printed on failure.

| Gate | Passes when |
| --- | --- |
| `call_sequence` | Every call in the required sequence was made, in order. |
| `result_shape` | Every `tools/call` response is a JSON-RPC response to the request just sent, with `resultType: "complete"`, `isError: false`, and a `structuredContent` object carrying an integer `snapshot.revision`. |
| `product_version` | `semidx_health.product_version` equals the version in `build.zig.zon`. |
| `semantic_contract_null` | Every result carries `semantic_contract_version: null`. |
| `parsers_available` | `semidx_health` lists every language with `parser.available: true`. |
| `diagnostics_visible` | `semidx_health` reports diagnostic counts, and the profile's known diagnostics are non-zero: `unsupported_construct` for both profiles, and `analysis_failed` for `fixture`. |
| `bounded_lists` | Every list tool result (`semidx_outline`, `semidx_repo_map`, `semidx_find_definitions`, `semidx_references`, `semidx_context`) carries `budget`, and at least one call per profile hits its limit and reports `truncated: true` with a total larger than the returned list. |
| `resolution_visible` | A known exact call is a `fact`; a known unresolvable call is `unresolved` with a designator target, no entity, and `missing`. |
| `refresh_revision` | `semidx_refresh` returns a revision greater than the one before the edit, and `previous_revision` equals that earlier revision. |
| `new_snapshot_observed` | Every call after the refresh reads the refreshed revision, and sees the edit. |
| `no_source_text` | Without `--allow-evidence-text`: health reports evidence text disabled, no result contains `source_text`, and no body text of the indexed source (including text added by the edit) appears in the stdout transcript. |
| `stream_discipline` | After stdin closes, stdout carries nothing but the responses already read, the process exits with status 0, stderr is read to its end and contains the exit line, and stdout is valid UTF-8. |
| `compact_budget` | `repository-copy` only: the default compact `semidx_repo_map`, `semidx_references`, `semidx_context`, and `semidx_health` transcripts are at most half the same calls with `detail: "full"` over the same snapshot (the Plan 007 budget, extended to references by Plan 009 and to health by Plan 016 Stage 4). |
| `response_budget` | `repository-copy` only: the default whole-repository `semidx_repo_map` either fits its response budget, or reports `budget_exhausted` and a `next_cursor`, and walking the cursor pages returns every source unit exactly once, each page reading the same snapshot revision and `files_total`. |
| `honest_degradation` | `fixture` only: the failing unit is reported with analysis `pending` and no definitions, and the outline counts it pending with its analysis failure; after an edit makes a unit unparsable, its definitions are absent from default `current` lookups, present as `stale` (same entity id) under `freshness: "any"`, and its unit reports analysis `stale`; the file outside every frontend's coverage is not a unit. It also asserts `working_copy.status: "in_sync"` on that same stale-unit result, proving the two axes side by side (ADR 014 D1). |
| `source_state_identity_deterministic` | `sync-trust` only: two `semidx_sync` calls over the same unchanged root report the same `snapshot.source_state_id`. |
| `unchanged_sync_stable` | `sync-trust` only: a `semidx_sync` call over an unchanged root reports `changed: false` and does not advance `snapshot.revision`. |
| `external_edit_detected` | `sync-trust` only: a graph-reading call made after an external edit and before a sync fails with text starting `semidx_preflight_out_of_date:`. |
| `graph_read_refusal` | `sync-trust` only: a preflight-blocked call's result carries no `structuredContent`. |
| `branch_switch_batch` | `sync-trust` only: one sync over a batch that changed, removed, and added a unit in the same edit reports all three non-zero in one `scan` outcome, and a later lookup confirms the removed unit's definition is gone from a default `current` lookup while the added unit's is present. |
| `corrected_post_sync_ranges` | `sync-trust` only: a sync's own result and the graph read immediately after it both report `working_copy.status: "in_sync"`, and the read's range reflects the edit. |
| `cursor_restart` | `sync-trust` only: a cursor issued before a sync that changes the revision fails to verify when retried after it. |
| `scan_failure_refusal` | `sync-trust` only: once the configured root disappears, a graph-reading call fails with text starting `semidx_preflight_scan_failed:`, and `semidx_health` reports `working_copy.status: "scan_failed"` without dropping its retained counts. |

The profile tests also carry assertions about specific graph content (for
example Plan 006's member definition and cross-unit call facts). They fail the
gate too, with the test's own failure output.

## Observations

Recorded in the evidence summary and in progress logs. They never fail the gate.

- elapsed milliseconds per call and from server start to the first response;
- transcript bytes per call;
- source-unit and byte counts of the root;
- diagnostic counts by kind, and current fact and unresolved assertion counts;
- the refresh scan outcome;
- the compact-to-full size ratios behind `compact_budget`.

Latency and size are not hard gates. They vary across machines, build modes, and
repository growth, and a gate that fails for those reasons would train people to
ignore it. A trend worth enforcing becomes a hard gate only with a documented
bound that stays stable across those.

## Evidence Summary

Each passing profile prints lines prefixed `gate:`:

```text
gate: profile fixture: first response <ms> ms after start
gate: hard pass refresh_revision: <before> -> <after>
...
gate: observation root: temporary directory of <n> fixtures/vertical-slice files (<bytes> bytes) and tool.py
gate: observation semidx_health {}: <ms> ms, <bytes> bytes
...
gate: observation refresh: revision <a> -> <b>, changed <n>, added <n>, removed <n>, analyzed <n>, entity ids preserved <bool>
```

`hard pass` lines name the gates above with what they saw; `observation` lines
are the values above. The Zig build runner shows each test's stderr under a
`failed command:` heading even when the test passes: the build summary and the
exit status are the result. A release candidate cites the command, its result,
and these lines; the
[Plan 008 progress log](../reports/008_habit_loop_release_gate_progress.md#stage-4-release-candidate-evidence)
records the first run.

## What The Gate Does Not Prove

- Support for any language. Coverage is the frontends' declared coverage in
  the [capability matrix](../spec/capability_matrix.md).
- A stable semantic contract or stable tool shapes.
- Persistence, HTTP, or any remote operation: none exists.
- Behavior of any hosted MCP client, or what such a client transmits onward.
- Performance on repositories other than the three profile roots.
- That the optional Jev ranking projection never calls its provider on a
  working-copy mismatch. That guarantee holds by construction — a mismatch
  fails closed before `semidx_rank_context`'s own handler runs, so it never
  reaches the provider — and is proven with a counting fake provider at the
  unit level (`src/mcp/root.zig`, [Plan 016](../plans/016_trustworthy_working_copy_sync.md)
  Stage 3), not by this gate: exercising it over stdio would need either live
  TypeSafe credentials the operator does not have ([Plan 015](../plans/015_optional_jev_ranking_projection.md)
  is blocked on exactly that) or a local mock HTTP endpoint, which is outside
  this plan's scope.

## Extending The Gate

- **A new assertion** is a hard gate only when it checks behavior an agent
  relies on in the habit loop and holds on every machine that meets the
  prerequisites. Add it to the table above and to the profile, and print it as a
  `hard` line. Anything else is an observation.
- **A new profile** needs a root that shows something the existing profiles
  cannot, a temporary directory, the full required call sequence, and a row in
  [Profiles](#profiles). Add it to the `preview-gate` step in `build.zig`.
- Do not add counts of tests, files, or languages, or broad benchmarks, as
  gates.
