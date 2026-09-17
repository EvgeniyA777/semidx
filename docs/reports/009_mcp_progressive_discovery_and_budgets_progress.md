---
title: "MCP progressive discovery and response budgets progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# 009: MCP Progressive Discovery And Response Budgets Progress

Companion log for
[docs/plans/009_mcp_progressive_discovery_and_budgets.md](../plans/009_mcp_progressive_discovery_and_budgets.md).

## Current Status

Stage 1 is complete: the baseline sizes, the client observation, the hard
gates, and the shape decisions later stages follow are recorded below.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 1: Evidence refresh and budget targets | Completed (`1f95838`) | Baseline structured and transcript sizes over this repository at `2353145`, one real-client observation, hard gates, soft observations, and the default response budget target. No behavior change. |
| Stage 2: Compact `semidx_references` | Completed (`9f4f3c2`) | `semidx_references` takes `detail` (`compact` default, `full`). Compact renders each listed target once, with its existence claim, and names a relationship end that is a listed target by `{id}`; the other end, resolution, producer, and evidence are compact. `writeString` at `limit` 1000: 24,716 transcript bytes against 56,964 full (43%), now a `compact_budget` hard gate. |
| Stage 3: Truncation guidance | Completed (`ce55c9f`) | Cut lists in `semidx_repo_map`, `semidx_find_definitions`, `semidx_references`, and `semidx_context` carry `narrowing_hints` naming declared arguments to narrow or raise; complete results carry none. |
| Stage 4: Repository outline | Completed | New `semidx_outline` lists the directories and files directly under a directory with unit, language, analysis, diagnostic, and definition counts and no definition entities. The root outline of this repository is 4,610 transcript bytes against 157,047 for the compact whole-repository map (2%). It is step 2 of the gate's required call sequence. |

## Plan Readiness Gate

Applied on 2026-09-17 before Stage 1. Plan 008 is completed
(`lifecycle: completed`, closed in `f62564c`), so the start rule holds, and it
produced gate evidence, so this plan uses it instead of Plan 007's numbers.
Scope, non-scope, stage order, verification commands, and DoD are explicit; no
hard fail.

The plan leaves shape choices to the executor. They are decided here so later
stages do not guess:

- **Hints** are one field, `narrowing_hints`, present only when a list in the
  result is truncated or the response budget is exhausted. Each hint is
  `{list, action, arguments}`: `list` names the truncated list (or `response`
  for the budget), `action` is one of `narrow`, `raise`, `lower`, or
  `continue`, and `arguments` names declared arguments of the same tool. Hints
  are derived only from which list truncated and which arguments the call
  already gave; they never look at entity names, paths, or counts.
- **Outline** is a new tool, `semidx_outline`, advertised right after
  `semidx_health`. Its `path_prefix` names a directory (trailing `/` optional,
  omitted for the root) and it returns the immediate children: directories with
  cumulative counts and files with their unit. Counts cover current top-level
  and nested definitions, units by language and analysis state, and diagnostics
  by kind. It lists no definition entities.
- **Response budget** is a declared argument `max_response_bytes` on
  `semidx_repo_map`, `semidx_outline`, `semidx_find_definitions`,
  `semidx_references`, and `semidx_context`. Each whole item (a map file, an
  outline entry, a definition, a relationship, a diagnostic, a context focus
  entity, a traversal edge) is rendered on its own first and appended only when
  the structured result stays within the budget; the first item of a response
  is always appended so a continuation always advances. Once one item is
  refused, no later item is appended. The result reports `budget_exhausted` and,
  when it is true, `omitted_by_budget` counts per list. Default 32,000 bytes,
  maximum 2,000,000 (see Stage 1 for why).
- **Cursors** are offered by `semidx_repo_map`, `semidx_outline`,
  `semidx_find_definitions`, and `semidx_references`, whose items come in one
  deterministic order. `semidx_context` returns several lists per focus and gets
  no cursor; its hints point at `entity_id`, `direction`, and the limits
  instead. A cursor is an opaque string encoding the tool, the snapshot
  revision, a hash of the canonical arguments, and the position of the next
  item. Canonical arguments are every declared argument with defaults applied,
  except `cursor`, `limit`, and `max_response_bytes`, so a caller may change the
  page size between pages. A cursor from another tool, revision, or argument set
  is a tool error (`isError: true`) naming which of those differs. A rebuilt
  index publishes revisions above the old ones (`Graph.idFloor`), so a revision
  number never names two graph states within one process.
- **Traversal** extends `semidx_context` with `direction` (`both` default,
  `incoming`, `outgoing`) and `depth` (1 default, maximum 3). At depth 1 the
  result is unchanged except that `direction` can omit one list. At depth 2 or
  3 every entity is rendered in full at its first occurrence in the response and
  named by `{id}` afterwards, and a `traversal` object lists the edges found
  beyond the first step with their `distance` and the `from` entity they were
  found from. Only entities reached through listed edges are expanded, each at
  most once, so cycles end.
- **Documentation** for the new surfaces is written once, in Stage 8, into
  `docs/mcp/local_preview.md` and the capability matrix; code stages record
  their shapes here. That keeps one rewrite of the reference instead of six
  partial ones on the same branch.

Drift check: the constitution, `SPEC.md`, `CORE.md`, and `CONFORMANCE.md` need
no change because outline, budget, hint, cursor, and traversal fields are MCP
projection behavior, not graph semantics, a contract, or a core kind.
`GLOSSARY.md` has no entries for these terms; `docs/mcp/local_preview.md` owns
*outline*, *response budget*, *narrowing hint*, and *cursor* as used for the
preview (recorded here per the documentation policy). Documents to align at
closure: `docs/mcp/local_preview.md`, `docs/mcp/habit_loop_gate.md`,
`docs/spec/capability_matrix.md`, `docs/agent-policy/tooling.md` (first-pass
flow), `MEMORY.md`, Follow-up 009 and its index.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Compact references keep claim honesty | Compact output drops resolution, producer, freshness, or turns a designator into an entity | Integration test over `Server.handleLine` | Compact and full references over one snapshot | Unresolved outgoing call stays a designator with `missing` | `src/mcp/root.zig` tests; dogfood `writeString` |
| Hints are guidance, not claims | A hint appears on a complete result, or names an undeclared argument | Integration test | Truncated versus untruncated call of each list tool | Untruncated result has no `narrowing_hints` | `src/mcp/root.zig` tests |
| Outline counts are exact | Directory counts disagree with the units under them | Integration test plus dogfood cross-check | Outline totals against `semidx_health` and `semidx_repo_map` | Language filter, unknown prefix, truncated children | `src/mcp/root.zig` tests; dogfood |
| Budget never cuts JSON or hides omission | A list looks complete while items were omitted | Integration test | Tiny `max_response_bytes` on every budgeted tool | Budget smaller than one item still returns one | `src/mcp/root.zig` tests; gate `response_budget` |
| Cursors are snapshot-scoped | A page mixes revisions, or skips or repeats items | Integration test | Walk every page and compare with one unbounded call | Refresh between pages; other tool; other arguments; malformed cursor | `src/mcp/root.zig` tests; dogfood map walk |
| Traversal is bounded and honest | Cycles repeat, entities render twice, unresolved edges read as facts | Integration test over a recursive fixture | Depth 2 over a cycle and a repeated neighbor | Depth 1 output unchanged; designators never expanded | `src/mcp/root.zig` tests; dogfood depth-2 call |
| Habit loop still passes | New defaults break the gate's calls or sequence | Runtime smoke | `zig build preview-gate` | Outline added to the required sequence | Both profiles |

## Stage 1: Evidence Refresh And Budget Targets

Changed files: this log.

### Baseline

Measured at `2353145` (Plan 008 tree, no behavior change since `97a07e0`) with
`zig-out/bin/semidx-mcp --root .` over this repository (68 units, snapshot
revision 90), one request per line in `2026-07-28` form, Debug build. Transcript
bytes are the response line as the stdio client reads it; structured bytes are
`structuredContent` re-serialized without whitespace. The whole-repository map,
the `writeString` references, and the `health` contexts match the Plan 008 gate
observations byte for byte.

| Call | Transcript bytes | Structured bytes |
| --- | ---: | ---: |
| `semidx_health` | 6,619 | 3,059 |
| `semidx_repo_map` `{}` (compact, 68 files) | 155,339 | 71,961 |
| `semidx_repo_map` `limit` 1000 | 155,341 | 71,962 |
| `semidx_repo_map` `limit` 1000, `full` | 327,269 | 151,989 |
| `semidx_repo_map` `path_prefix` `src/mcp/` (5 files) | 25,641 | 11,713 |
| `semidx_repo_map` `path_prefix` `src/core/` (7 files) | 22,931 | 10,494 |
| `semidx_repo_map` `path_prefix` `src/frontends/` (5 files) | 29,879 | 13,672 |
| `semidx_repo_map` `path_prefix` `tests/` (6 files) | 15,083 | 6,877 |
| `semidx_references` `writeString` in `src/mcp/protocol.zig`, `limit` 1000 (heavy, 23 calls) | 56,927 | 26,450 |
| `semidx_references` `scanDir` (ordinary, 2 relationships) | 6,786 | 3,038 |
| `semidx_context` `scan` in `src/source/discovery.zig` (ordinary) | 11,794 | 5,378 |
| `semidx_context` `health` in `src/mcp/tools.zig` (default limits) | 40,756 | 18,756 |
| `semidx_context` `health`, `relationship_limit` 500 (heavy) | 60,962 | 28,095 |
| `semidx_context` `health`, `relationship_limit` 500, `full` | 153,194 | 71,486 |
| `semidx_context` `init` (multi-focus by name) | 59,524 | 27,682 |

### Payload Copies

- **Maintained stdio client** (`tests/mcp_stdio_client.zig`): sees both copies.
  Every successful result carries `structuredContent` and a text block with the
  same object serialized, so transcript bytes are about twice the structured
  bytes plus the envelope (155,339 against 71,961 above).
- **Real client, observation only:** the Claude Code VS Code extension session
  that executed this stage called the repository's registered `semidx` server
  for `semidx_context` `health` with `relationship_limit` 500 (28,095
  structured bytes). The model received one copy of the object as text, inline,
  with no warning and no spill to a file. No larger call was made, so where that
  client starts warning or spilling was not observed. This is one client, one
  call, and is not a gate.

### Hard Gates And Observations

Hard gates (stable because they compare renderings of one snapshot or check
shape, never absolute bytes):

- Plan 007's `compact_budget` stays: compact map and context at most half of
  full, measured with a budget large enough that neither is cut.
- Compact `semidx_references` for `writeString` (`limit` 1000) is at most half
  of the same call with `detail: "full"`: the Stage 2 "materially smaller" bar.
- `response_budget` (new, `repository-copy`): the default whole-repository
  `semidx_repo_map` either fits or reports `budget_exhausted` with a
  `next_cursor`, and walking the cursor pages returns every file exactly once
  with the same `files_total` on every page.
- Every result stays valid JSON with `truncated` true whenever fewer items than
  the total were returned (existing `result_shape` and `bounded_lists`, now over
  the new tools too).
- `call_sequence` gains `semidx_outline` after `semidx_health`.

Soft observations (printed, never failing): transcript bytes per call, the
outline's size against the whole-repository map, and the page count of the
map walk.

### Default Response Budget

32,000 structured bytes, about 64 KB on a transcript that carries both copies.
It is just above the largest ordinary default call measured here (the
multi-focus `init` context at 27,682) and near the largest result observed
passing through a real client without warning (28,095), so ordinary habit-loop
calls are not cut, while the flat whole-repository map (71,961) is. Explicit
`max_response_bytes` up to 2,000,000 recovers every current result in one call,
including the full map (151,989).

## Stage 2: Compact `semidx_references`

Changed files: `src/mcp/tools.zig`, `src/mcp/root.zig` (test),
`tests/mcp_dogfood_test.zig`, `docs/mcp/habit_loop_gate.md` (`compact_budget`
row), this log.

- `writeRelationship` takes the ids already in view instead of one focus id,
  so context passes its focus and references pass every listed target: a
  recursive call or a call between two targets names both ends by id.
- Full mode renders exactly what the tool rendered before, plus
  `budget.detail`.
- The new test covers a compact call with one fact and one unresolved outgoing
  call (designator, `missing`, no entity; resolution, producer, freshness, and
  evidence path and lines on both), an incoming call, and full mode's
  resolution method and explanation, producer versions, byte offsets, entity
  extension and revisions, and existence assertion id and revision.

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-mcp --summary all` | Pass; 22 passed, 1 skipped (the dogfood recovery test) |
| `zig build dogfood --summary all` | Pass; 10/10 steps, 5/5 tests; `compact_budget` 47% map, 43% references, 39% context |

## Stage 3: Truncation Guidance

Changed files: `src/mcp/tools.zig`, `src/mcp/root.zig` (test), this log.

- `narrowing_hints` is written by `Hints.write` only when a list was cut. Each
  hint is added once per list and action, and one that would name no argument
  is dropped, so a limit already at its maximum is never suggested for raising
  and an argument the call already gave is never suggested again (except
  `path_prefix`, which a longer prefix narrows, and `resolution`/`direction`
  when they still select everything).
- Lists and hints: `semidx_repo_map` `files` (narrow `path_prefix`,
  `language`; raise `limit`) and `definitions` (raise `definitions_per_file`);
  `semidx_find_definitions` `definitions` (narrow `name`, `path`, `language`,
  `role`, `resolution`; raise `limit`); `semidx_references` `targets` (narrow
  `entity_id`, `path`, `language`) and `relationships` (narrow `path` and
  `language` when targets are named, `direction` when `both`, `resolution`
  when `any`; raise `limit`); `semidx_context` `focus` (narrow `entity_id`,
  `path`, `language`), `incoming`/`outgoing` (raise `relationship_limit`), and
  `diagnostics` (raise `diagnostic_limit`).
- `Args(tool).given`, `unset`, and `maximum` check every name against the
  tool's declarations at compile time, so a hint cannot name an undeclared
  argument; the test also checks that at run time for every hint it sees.

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-mcp --summary all` | Pass; 23 passed, 1 skipped |

Not rerun: `zig build dogfood`. Hints only add a field to cut lists, and no
gate reads or forbids it; the gate runs again at Stage 5, which changes
defaults.

## Stage 4: Repository Outline

Changed files: `src/mcp/tools.zig`, `src/mcp/root.zig` (dispatch and tests),
`tests/mcp_gate.zig`, `tests/mcp_dogfood_test.zig`,
`tests/mcp_fixture_gate_test.zig`, `tests/mcp_smoke_test.zig`,
`docs/mcp/habit_loop_gate.md` (call sequence, `bounded_lists`,
`honest_degradation`), this log.

- `semidx_outline` takes `path_prefix` (a directory; trailing `/` optional;
  omitted for the root), `language`, and `limit` (100, max 1000 entries).
  Entries are sorted by name. A directory entry has `name`, `path` ending in
  `/`, `type: "directory"`, and cumulative `counts` (`units`, `languages`,
  `analysis`, `diagnostics`, `top_level_definitions`,
  `nested_definitions`); a file entry has `type: "file"`, its compact `unit`,
  and `counts` without the unit-level fields its unit already states. The
  result carries `path_prefix` as normalized, `entries_total`, `truncated`,
  `totals` over every matched unit, hints, and `budget`.
- Definition counts use the same selection as `semidx_repo_map` (current
  definitions; empty container path is top-level), computed in one pass over
  entities and one over diagnostics per call. No source text is read; paths
  are the unit paths.
- The gate requires `semidx_outline` after `semidx_health`. The
  `repository-copy` profile checks that outline totals equal health's unit
  count and that entry counts add up to it, and observes the outline's size
  against the whole map; the `fixture` profile checks the outline counts the
  failing unit pending with its analysis failure and does not list the
  unindexed file.

### Verification

| Command | Result |
| --- | --- |
| `zig fmt --check build.zig src tests` | Pass |
| `zig build test-mcp --summary all` | Pass; 24 passed, 1 skipped |
| `zig build preview-gate --summary all` | Pass; 14/14 steps, 6/6 tests; outline 4,610 bytes (repository copy) and 4,458 bytes (fixture) |
