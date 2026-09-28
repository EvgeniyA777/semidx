---
title: "Trustworthy working-copy synchronization progress"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-27"
---

# 016: Trustworthy Working-Copy Synchronization Progress

Companion log for
[docs/plans/016_trustworthy_working_copy_sync.md](../plans/016_trustworthy_working_copy_sync.md).

## Current Status

**Plan complete (all six stages). One residual item, explicitly not a
Definition-of-Done blocker (see Stage 6): the external-repository real-task
evaluation Stage 5's "Required work" names was not run.**

## Start Rule: Readiness Evidence

### Environment record (2026-09-27)

- Branch: `dev`. Working tree clean at start (`git status --short --branch`:
  `## dev...origin/dev`, no ahead/behind, no dirty files).
- Last commit before this stage: `7f47a84 docs: block Jev evaluation pending
  direct access`.
- Toolchain: `./scripts/check-zig-version.sh` reported "Zig version 0.16.0
  matches semidx target".
- Product version: `0.1.0-preview.4` (`build.zig.zon`).
- Snapshot health at start (`semidx_health`): revision 135, 80 units (77
  current, 3 pending, 0 stale), 1,189 definitions, 8,658 recorded assertions
  (3,743 current facts, 4,915 current unresolved, 0 approximate), diagnostics
  `analysis_failed: 3`, `unsupported_construct: 184`, `confirmed_absence: 2`,
  no recovery pending.
- Existing tool list (from `docs/mcp/local_preview.md`): `semidx_health`,
  `semidx_outline`, `semidx_repo_map`, `semidx_find_definitions`,
  `semidx_references`, `semidx_context`, `semidx_refresh`, and the
  consent-gated experimental `semidx_rank_context`.

### Required reading (Start Rule)

Read in full before this log was created: `RULES.md`,
`ARCHITECTURE_CONSTITUTION.md`, `MEMORY.md`, `SPEC.md`,
[ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md),
[proposed ADR 014](../adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md),
[Follow-up 021](../followups/021_snapshot_revision_is_not_a_content_identity.md),
the [local MCP reference](../mcp/local_preview.md), and the
[habit-loop gate](../mcp/habit_loop_gate.md).

### Plan Readiness Gate

Applied against the plan document as committed. No hard-fail condition found:

- Product/runtime behavior is explicit and consistent with `RULES.md`,
  `MEMORY.md`, ADR 005, proposed ADR 014, and current MCP implementation
  behavior (`MEMORY.md` already names Plan 016 as the next trust-first
  correction and cites the same regression).
- Scope and non-scope are both explicit and mutually consistent (no watcher,
  no persistence, no stale bypass, no source-body rendering, no Jev
  quality/version work).
- The one key decision gate (ADR 014 acceptance) has an explicit stop/resume
  rule owned by Stage 0.
- No stage depends on a later stage's outcome; each stage names concrete
  files, required behavior, a Done-when condition, and verification commands.
- DoD items are observable through fixtures, contract tests, gate output, and
  committed docs.
- The Risk Matrix maps every named guarantee to a verification level and a
  negative/bypass case.
- Runtime constraints (offline, credential-free, sequential stdio loop) are
  named explicitly, including the stop rule if dispatch is found to overlap.
- No internal contradiction found between the plan, ADR 014, `SPEC.md`'s
  "Optional outbound data" entry, or `MEMORY.md`'s current-state section.

**Verdict: ready for staged execution**, matching the plan's own stated
verdict.

## Stage 0: Accept The Trust Contract And Freeze Fixtures

### ADR 014 constitutional review

Independently re-checked ADR 014's own "Constitutional Decision Test" section
against all eight questions in `ARCHITECTURE_CONSTITUTION.md` §11: source-state
identity and working-copy status are scan/comparison metadata, establish no
graph relationship, create no node, and do not change frontend coverage,
core-kind roster, entity identity rules, or reconciliation. The distinction
strengthens §3 at the MCP surface (analysis freshness and working-copy sync no
longer collapse into one `current` label) rather than weakening any clause.
No open objection found. **Accepted unchanged** —
`docs/adr/014_distinguish_snapshot_analysis_from_working_copy_sync.md`
frontmatter moved `lifecycle`/`status` from `proposed` to `accepted`; its
"Terminology Ownership" section updated to say Stage 0 completed the vocabulary
handoff.

### `SPEC.md` and `GLOSSARY.md`

- `SPEC.md`: added a "Working-copy synchronization" row to "Requirements Still
  To Specify", stating the two-axis distinction, the source-state identity
  encoding's inputs/exclusions, the fail-closed preflight requirement
  (including blocking the optional ranking projection), and `semidx_sync`'s
  idempotence, alongside the existing "Optional outbound data" row's style.
- `GLOSSARY.md`: added **source-state identity**, **sync preflight**, and
  **working-copy status** in alphabetical position, each linking back to ADR
  014 and (for source-state identity) Follow-up 021.

### Regression fixture

Committed `fixtures/working_copy_sync/`: nine synthetic Zig units
(`units/unit_01.zig` .. `unit_09.zig`, one trivial function each) plus
`units/unit_03_edited.zig`, a byte-changed variant of unit 3. `README.md`
documents the reproduction sequence: index the nine units, overwrite
`unit_03.zig` on disk with the edited variant from outside the server (a
stand-in for "another process"), call a graph-reading tool without syncing
first (today this still answers `current` from the untouched snapshot — the
exact defect ADR 014 D1/D4 closes), then sync and repeat to confirm the
corrected range and `working_copy.status: "in_sync"`. No content from the
external Java repository the original regression was observed on is used;
every unit is synthetic and new. Stage 3 turns this into an executable gate
test once fail-closed preflight exists to make the pre-sync call actually fail
closed.

### Frozen identity vectors and health examples

- `fixtures/working_copy_sync/identity_vectors.md` freezes the *inputs* (not
  hashes — `semidx-source-state-v1` does not exist until Stage 1) for the
  seven cases the plan's "Source-State Identity Encoding" section names:
  empty, one-unit, reordered-input, byte-change, path-change,
  diagnostic-change, and policy-change, each naming which fixture files and
  which policy/diagnostic delta it uses.
- `fixtures/working_copy_sync/health_examples.md` freezes illustrative
  compact/full `semidx_health` result shapes under ADR 014 D5 (including
  `out_of_date` and `scan_failed` compact examples), so Stage 2/4 implement
  against a decided shape rather than inventing one alongside the code.

### Baseline discovery-scan measurement (2026-09-27)

`zig build preview-gate --summary all` (used as the measurement instrument;
it is not itself a Stage 0 deliverable) reported, before any working-copy-sync
code exists:

- `fixture` profile: 7 units, 3,483 bytes; first response (server start
  through the first `semidx_health` reply, which includes discovery and full
  index build) 75 ms; that `semidx_health` call itself 72 ms, 8,833 bytes.
- `repository-copy` profile: 90 units, 1,455,282 bytes; first response 1,193
  ms; that `semidx_health` call itself 1,190 ms, 8,871 bytes. Every later call
  in the same run is single-digit milliseconds because it reads the already
  published snapshot rather than rescanning.

This is a combined discovery-plus-index-build number, not an isolated
discovery-scan cost: nothing in the current implementation exposes a scan
timing separate from full startup. Stage 1-3 must either isolate scan-only
timing when they add the preflight, or note in their own verification that the
Stage 5 "exact preflight cost is visible" observation still needs it. Recorded
here only as the pre-change baseline the future per-call preflight cost should
be compared against.

### Verification run

- `./scripts/check-zig-version.sh`: "Zig version 0.16.0 matches semidx
  target".
- `zig fmt --check build.zig src tests`: clean (also checked the new fixture
  `.zig` files individually).
- `zig build preview-gate --summary all`: 15/15 steps succeeded, 6/6 tests
  passed (unrelated to this stage's changes; run to capture the baseline
  above, not because Stage 0 changed any source).
- `mcp__semidx__semidx_health` at Stage 0 start: revision 135 (recorded above
  under Environment record).

### Stage 0 stop-rule check

No stop condition triggered: the accepted ADR permits no graph read after
mismatch/scan failure, and source-state identity is scoped to source discovery
input, never semantic assertions.

**Done when:** ADR 014 accepted (done); `SPEC.md`/`GLOSSARY.md` own the
contract vocabulary (done); fixtures/examples committed (done); this progress
log records a passing readiness review (done). Stage 0 complete.

## Stage 1: Deterministic Source-State Identity

### What shipped

- `src/source/scan.zig`: `SourceScan` gained `excluded_directories: []const
  []const u8` — the effective exclusion policy, owned by the scan's arena and
  sorted, captured at scan time so nothing later reads mutable
  caller-owned `Options` memory.
- `src/source/discovery.zig`: `scanDir` now dupes and sorts
  `options.excluded_directories` into the new field via
  `ownedSortedExclusions`. No other discovery behavior changed; the existing
  unit/diagnostic scan and sort behavior is untouched.
- `src/source/identity.zig` (new): implements `semidx-source-state-v1`.
  `calculate(gpa, scan)` sorts its own scratch copies of `scan.units` (by
  path), `scan.diagnostics` (by path, then kind, then message — the plan's
  required canonicalization, since the existing discovery-facing comparator
  only orders by path then message and cannot separate two diagnostics of
  different kinds sharing both), and `scan.excluded_directories` (byte order)
  before hashing, so the identity does not depend on the order the caller
  happened to hold them in. The encoding is version marker, then budgets
  (`max_file_bytes` u64 BE, `max_units`/`max_depth` u32 BE), then the sorted
  exclusion list (u32 BE count, each a length-prefixed string), then the
  sorted units (u32 BE count, each a length-prefixed path, length-prefixed
  language tag, and the raw 32-byte content digest), then the sorted
  diagnostics (u32 BE count, each a length-prefixed kind tag, path, and
  message). Every variable-length string is `u32` big-endian length then
  bytes, so no adjacent fields can be split at the wrong boundary. `toHex`/
  `fromHex` render and parse exactly 64 lowercase hex characters; `fromHex`
  rejects uppercase, since this module never produces it.
- `src/source/root.zig`: exports `identity`, `SourceStateId`, and
  `sourceStateId` (= `identity.calculate`).
- No per-unit `ContentId`, registry correspondence, graph identity, or
  analyzer behavior changed. `grep -rn "SourceScan{" src tests` before this
  change found no hand-built `SourceScan` literal outside `discovery.zig`, so
  adding the required field could not silently break another constructor.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-core --summary all`: 108/109 passed (1 pre-existing skip),
  including 11 new `identity.zig` tests: empty-vs-one-unit distinctness,
  input-order independence across units/diagnostics/exclusions, and one
  identity change each for byte, path, language, added diagnostic,
  diagnostic-kind-only difference, exclusion-policy, and budget — plus hex
  round-trip/rejection and two independent `discovery.scanDir` calls over the
  same temporary tree agreeing.
- `zig build test-core -Dgrammars-dir=/nonexistent --summary all`: 108/109
  passed, confirming `src/core/` (and this identity code, which lives in
  `src/source/` beside it in the same test binary) stays parser-free.
- `zig build test --summary all`: 336/338 passed (2 pre-existing skips),
  confirming the frontends, MCP server, and dogfood/gate lanes are unaffected.

### Fixture note

`fixtures/working_copy_sync/identity_vectors.md` updated to record that Stage
1's seven vectors are proven as unit tests directly against small in-memory
scan values (matching the cases the file already described), not by
duplicating `units/unit_01.zig`..`unit_09.zig` file-by-file into each vector;
that fixture set remains reserved for the Stage 3 gate regression test. No
third-party reference hash is pinned — Stage 1's "Done when" is fixed vectors
passing and two independently built equivalent scans matching, both of which
the test file proves by equality/inequality between computed values.

### Stop-rule check

No stop condition triggered: the identity input stayed source discovery data
(paths, languages, content digests, diagnostics, policy) and never touched
graph assertions or entities.

**Done when:** fixed vectors pass (done); two independently built equivalent
scans match (done); source discovery behavior otherwise unchanged (done —
existing discovery tests still pass unmodified). Stage 1 complete.

## Stage 2: Idempotent Sync Coordinator

### What shipped

- `src/mcp/sync.zig` (new): `run(target: Target) Error!Outcome` performs one
  scan, computes its source-state identity, and compares it against
  `target.source_state_id.*`. Unchanged and not poisoned: returns `.unchanged`
  without touching the index, snapshot, or entity ids. Otherwise: rebuilds a
  poisoned index first if needed (same fresh-index-above-the-id-floor
  recovery a plain refresh always used), then reconciles through
  `Index.applyScan`/`publish`, retires the old index, and pairs the newly
  published snapshot with the newly observed identity. `Target` holds pointers
  into the caller's fields (`index`, `snapshot`, `retired`, `poisoned`,
  `rebuilds`, `last_scan`, `source_state_id`) rather than owning them, so
  `Server` stays the single owner of that state and existing tests that reach
  into `server.poisoned`/`server.retired`/`server.snapshot` directly keep
  working unmodified. `Outcome` is a plain value (`unchanged`, `changed`,
  `scan_failed`, `rebuild_retry_failed`, `reconcile_failed`) — this module
  writes no tool JSON or error text, matching the plan's architecture
  boundary.
- `src/mcp/root.zig`: `Server` gained `source_state_id`, computed once in
  `init` from the same initial scan that seeds the index. The old
  `refresh`/`recoverFrom`/`rebuild` trio is replaced by `performSync` (calls
  `sync.run`, then renders exactly the same four failure messages the old
  `refresh` produced word for word, so no behavioral or wording change reaches
  a client) and `writeSyncResult` (the shared success envelope). Both
  `semidx_sync` and `semidx_refresh` dispatch to `performSync`.
- `src/mcp/tools.zig`: added `Tool.semidx_sync` (zero arguments, like
  `semidx_refresh`) with its own description; generalized the
  `readOnlyHint`/`destructiveHint`/`idempotentHint` annotation logic (was
  `tool == .semidx_refresh`) to cover both tools; reworded `semidx_refresh`'s
  description to name the alias relationship.
- Result shape (both tools identically): the existing `previous_revision`,
  `entity_ids_preserved`, `scan`, `units`, `diagnostics` fields, plus new
  `snapshot.source_state_id`, `working_copy.status` (always `"in_sync"` here
  — a completed sync's own post-condition), `working_copy.observed_source_state_id`,
  and a new top-level `changed: bool`. This matches the plan's Fixed Runtime
  Contract "Result Envelope" shape for these two tools now, ahead of Stage 3
  wiring the same envelope into every other tool's result — `beginStructured`
  itself is untouched in this stage, so this envelope is currently
  hand-written in `writeSyncResult` rather than shared; Stage 3 folds it back
  into `beginStructured` once every tool needs it.
- `tests/mcp_smoke_test.zig`: updated the three hardcoded tool-list-length
  assertions (7→8, 8→9) and the ordered tool-name list to include
  `semidx_sync` right after `semidx_refresh`.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp --summary all`: 80/81 passed (1 pre-existing skip),
  including a new test proving: an unchanged working copy leaves revision,
  entity ids, and the identity untouched through `semidx_sync`; a real change
  is detected and published exactly once; a second sync after that stays
  idempotent at the new state; and `semidx_refresh` produces the same
  envelope fields (`snapshot.source_state_id`, `working_copy`, `changed`)
  through the same coordinator.
- `zig build test --summary all`: 337/339 passed (2 pre-existing skips). This
  includes the pre-existing exhaustive allocation-failure-injection recovery
  tests (`expectRecoveryAt`, run at every allocation point of the sync path,
  once with one-shot failures and once with sticky failures) — they still
  converge with the coordinator moved into `sync.zig`, proving the refactor
  did not change the recovery guarantees, only where the code that provides
  them lives.
- `zig build preview-gate --summary all`: 15/15 steps, 6/6 tests, both
  profiles pass; dogfood recovery over 92 units still finds 32 failure points
  and rebuilds correctly under both one-shot and sticky injected failures.

### Stop-rule check

No stop condition triggered: `sync.zig` never writes tool JSON or schema text
(root.zig still owns every rendered message and field name), and dispatch
stayed strictly sequential — no evidence of overlapping calls was found, so no
serialization boundary beyond the existing stdio loop was needed.

**Done when:** sync is idempotent on unchanged input (done); changed input
publishes once (done); every existing refresh recovery injection still
converges (done, verified at every allocation point under both failure
modes). Stage 2 complete.

## Stage 3: Fail-Closed Read Preflight

### What shipped

- `src/mcp/sync.zig`: added `preflight(gpa, io, root, retained) ->
  Allocator.Error!Preflight`, a read-only counterpart to `run`: one discovery
  scan, compared against `retained`, returning `.in_sync`/`.out_of_date`/
  `.scan_failed` plus the observed identity (null on scan failure). It never
  touches the index or snapshot, unlike `run`.
- `src/mcp/tools.zig`: `Context` gained `source_state_id: []const u8`,
  `working_copy_status: WorkingCopyStatus`, and `observed_source_state_id:
  ?[]const u8`, all set by the caller before a tool runs. `beginStructured`
  (shared by all seven tools that call it) now renders
  `snapshot.source_state_id` and `working_copy{status,
  observed_source_state_id}` from these fields — the same envelope
  `writeSyncResult` hand-wrote in Stage 2, now generalized and folded back
  in, so `writeSyncResult` was simplified to just call `beginStructured`.
- `src/mcp/root.zig`: `callTool` now runs `self.preflight()` before dispatch
  for `semidx_outline`, `semidx_repo_map`, `semidx_find_definitions`,
  `semidx_references`, `semidx_context`, `semidx_rank_context` (the ADR 014
  D4 list), and separately for `semidx_health` (D5). For the six D4 tools, a
  non-`in_sync` preflight short-circuits before the tool's own handler ever
  runs, via `ctx.fail(...)` producing the plan's exact stable-prefixed text:
  `semidx_preflight_out_of_date: ...` or `semidx_preflight_scan_failed: ...`,
  each followed by the retained snapshot revision and source-state identity.
  Because the handler never runs, `semidx_rank_context`'s ranking provider is
  structurally never invoked on a mismatch — not a separate check, a
  consequence of the dispatch order. `semidx_health` always runs its own
  handler regardless of preflight status; it just reports whichever status
  the comparison found.
- `tests/mcp_fixture_gate_test.zig`: added an assertion that the post-sync
  `semidx_context` call (which already existed, to check the repaired unit's
  `stale` analysis) also reports `working_copy.status: "in_sync"` in the same
  result — ADR 014 D1's two axes proven side by side in one call, not just
  separately.
- `src/mcp/root.zig` tests: rewrote the two assertions in "refresh publishes a
  new snapshot..." that depended on the old stale-answer behavior (an
  unrefreshed read after an external edit used to return `structuredContent`
  with stale data; it now fails closed) to assert the new fail-closed
  behavior instead, and added three new tests: idempotent
  `semidx_sync`/`semidx_refresh` behavior (Stage 2, described above), a test
  proving a blocked read leaves revision and graph entity count untouched and
  that a sync-then-retry returns the corrected range (using the exact
  three-line shift the external edit introduces, computed from the
  before-edit range rather than a hardcoded line number), and a test proving
  a counting fake `ranking.Provider` receives zero calls while the working
  copy is out of date and exactly one call once synced.
- `docs/mcp/local_preview.md`: updated the "What It Does" bullet, the Result
  Fields section (now describes the fail-closed contract for all six D4
  tools plus health's report-not-repair behavior), and the Errors table
  (two new rows for the preflight failure shapes). The "First Calls" section
  is deliberately left as Stage 4's scope (recommending `semidx_sync` first)
  per the plan's own stage boundary.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp --summary all`: 82/83 passed (1 pre-existing skip).
- `zig build test --summary all`: 339/341 passed (2 pre-existing skips),
  including the exhaustive allocation-failure-injection recovery tests
  (unaffected — they exercise `semidx_refresh` specifically, whose own
  internal scan is `sync.run`'s, not a separate preflight scan).
- `zig build preview-gate --summary all`: 15/15 steps, 6/6 tests, both
  profiles pass. Per-call latency in the evidence summary rose from ~0-3ms to
  ~8ms per call on the repository-copy profile (92 units) — the cost of one
  full discovery scan added before every graph-reading tool call. Recorded
  here as the first real (not combined-with-startup) preflight-cost
  observation; Stage 5 formalizes this measurement.

### Stop-rule check

No stop condition triggered: no `allow_stale_snapshot` bypass was added, and
the fail-closed behavior is unconditional for the six D4 tools (no flag or
argument weakens it).

**Done when:** the synthetic external-edit regression fails closed before
stale ranges can be rendered and succeeds only after sync (done — proven both
in the new root.zig test and reproduced structurally by the rewritten
"refresh publishes a new snapshot..." test). Stage 3 complete.

## Stage 4: Compact Health And Sequential Habit Loop

### What shipped

- `src/mcp/tools.zig`: `semidx_health` gained a `detail: "compact" | "full"`
  parameter (default `compact`), matching the pattern `semidx_repo_map`/
  `semidx_references`/`semidx_context` already use. Compact keeps: root,
  product/server identity, `snapshot.source_state_id`, `working_copy`, unit
  and diagnostic counts, per-language parser availability, recovery state,
  and the already-redacted `outbound_projection`. Full adds: graph
  entity/assertion counts, per-language `extensions`/`producer`/
  `entity_roles`/`relationship_kinds`/`coverage_note`, and `last_scan`. A
  `budget: {detail}` field reports which was rendered, matching the other
  detail-level tools. `evidence_text` stays in both, since whether the
  evidence-text opt-in is on is exactly the kind of trust-relevant fact the
  plan asked compact to keep.
- Measured on the repository-copy profile: compact health is 2,395 bytes vs.
  full at 9,376 bytes — 25% of full, well inside the required half.
- `tests/mcp_gate.zig`: `checkHealth` no longer assumes `graph` is present
  (it isn't, by default) and now also asserts `working_copy.status` is
  reported; `tests/mcp_dogfood_test.zig` adds an explicit compact-vs-full
  `semidx_health` size comparison, reusing the existing `expectAtMostHalf`
  helper (previously only for `semidx_repo_map`/`semidx_references`/
  `semidx_context`).
- `docs/mcp/habit_loop_gate.md`: the `compact_budget` gate row now names
  `semidx_health` alongside the other three tools it already covered.
- `docs/mcp/local_preview.md`, `README.md`, and
  `.agents/skills/semidx-code-exploration/SKILL.md`: the first-call sequence
  now starts with `semidx_sync`, demotes `semidx_health` to "call when a
  diagnostic summary is useful" rather than the mandatory first step, and
  states explicitly that `semidx_sync` and every call after it are dependent
  calls that must not be launched in parallel (ADR 014's own trust argument
  depends on this: a call racing an in-flight sync could observe either
  snapshot). `semidx_refresh` is described everywhere as the compatible
  alias, not a separate step. `semidx_health`'s tool description and the new
  `detail` parameter documentation make the compact/full split and the
  revision-vs-`source_state_id` distinction explicit at the schema level, not
  only in prose.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test-mcp --summary all`: 82/83 passed (1 pre-existing skip).
- `zig build test --summary all`: 339/341 passed (2 pre-existing skips).
- `zig build preview-gate --summary all`: 15/15 steps, 6/6 tests; the new
  `compact_budget` evidence line for health: `gate: hard pass compact_budget:
  semidx_health: 25% of full`.
- `./scripts/check-readme-stewardship.sh --all`: passed after the `README.md`
  quickstart update.

### Stop-rule check

No stop condition triggered: no output budget was exceeded, and every change
is prose/schema/detail-level rendering, not a semantic or contract change.

**Done when:** a fresh agent can follow the documented sequence without
inferring working-copy state from `current` (done — every doc surface now
states the two-axis distinction and the sync-first sequence); compact health
is materially smaller than full health on the repository-copy profile (done,
25%). Stage 4 complete.

## Stage 5: Habit-Loop Gate And External-Cost Evidence

### What shipped

- `tests/mcp_gate.zig`: added `Step.sync` as the new first entry of
  `required_sequence`, satisfied by whichever tool call is literally the
  first one a profile makes named `semidx_sync`. Later `semidx_sync` calls
  (there are several in the new profile) classify like `semidx_refresh`,
  matching Stage 2's shared coordinator. `checkHealth` now asserts
  `working_copy.status` is reported (a `diagnostics_visible` pass) instead of
  assuming `graph` is present.
- `tests/mcp_dogfood_test.zig` and `tests/mcp_fixture_gate_test.zig`: both now
  make `semidx_sync` their first call (`changed: false` asserted, since
  nothing has happened yet); everything else in both profiles is unchanged.
- `tests/mcp_sync_gate_test.zig` (new): the `sync-trust` profile, over the
  nine-unit fixture `fixtures/working_copy_sync/units/` Stage 0 froze exactly
  for this. One server process proves, in order: two `semidx_sync` calls over
  an unchanged root report the same `source_state_id` and revision
  (`source_state_identity_deterministic`, `unchanged_sync_stable`); a
  branch-switch-shaped batch (`unit_03.zig` changed, `unit_09.zig` removed,
  `unit_10.zig` added, all in one edit) applied from outside the server is
  detected by a blocked read before syncing
  (`external_edit_detected`/`graph_read_refusal`); one sync publishes the
  whole batch and reports `changed`/`removed`/`added` all non-zero in one
  scan outcome (`branch_switch_batch`); a read right after returns the
  corrected range and `working_copy.status: "in_sync"`
  (`corrected_post_sync_ranges`); a cursor issued before the sync fails when
  retried after the revision changed (`cursor_restart`); and once the root
  disappears entirely, a graph read fails with
  `semidx_preflight_scan_failed:` while `semidx_health` keeps answering,
  reporting `working_copy.status: "scan_failed"` without dropping its
  retained counts (`scan_failure_refusal`). A small local `rawCallTool`
  helper (over `Client.request` directly) was needed for the three calls this
  profile expects to fail: `Gate.call`/`Gate.sizedCall` assert success by
  design, which is correct for the other two profiles but wrong for a profile
  whose whole point is proving specific failures.
- `build.zig`: wired the new test file into `preview-gate` as a third
  dependency, with its own `fixtures/working_copy_sync` fixtures-dir option,
  the same pattern the `fixture` profile already uses.
- `docs/mcp/habit_loop_gate.md`: added the `sync-trust` row to Profiles, the
  new `Step.sync` entry to Required Call Sequence, eight new named hard-gate
  rows (`source_state_identity_deterministic`, `unchanged_sync_stable`,
  `external_edit_detected`, `graph_read_refusal`, `branch_switch_batch`,
  `corrected_post_sync_ranges`, `cursor_restart`, `scan_failure_refusal`), and
  an explicit note under "What The Gate Does Not Prove" naming the one Stage
  5 guarantee this gate does not exercise itself (see below).

### Zero Jev calls on mismatch: proven at the unit level, not by this gate

Stage 5's required list includes "zero Jev calls on mismatch" as a named hard
gate. This is already proven — a counting fake `ranking.Provider` receives
zero calls on a mismatch and exactly one once synced
(`src/mcp/root.zig`, Stage 3's "semidx_rank_context calls no provider when
the working copy is out of date" test) — but that proof runs at the Zig unit
level (`Harness`, in-process), not through the stdio gate. Exercising it
through the built binary over stdio would need either live TypeSafe
credentials (unavailable — Plan 015 is explicitly blocked on exactly this) or
a local mock HTTP endpoint, which is new test infrastructure outside this
plan's scope (Non-Scope: "No Jev quality evaluation, model change, provider
behavior change, release, version bump, HTTP transport, or new dependency").
Documented explicitly in `habit_loop_gate.md` rather than silently omitted or
faked as a stdio-level gate it is not.

### Residual item: external-repository real-task evaluation

Stage 5 also asks to "run one privacy-safe real-task evaluation on an
external repository and record whether stale graph data escaped, how many
manual reads remained, and how many extra tool round trips sync required."
This needs an actual external repository and an interactive session using
the MCP preview against it — not something this session can fabricate
evidence for without a repository to point it at. **Not done.** Flagged to
the operator; if they name a repository (or confirm using a fresh clone of a
public one, not committing its source or absolute paths), this item can be
completed as a follow-up to this stage rather than blocking Stage 6, since
the plan's own Stage 5 "Done when" bar (the canonical gate reproduces and
prevents the original failure mode, and preflight cost is recorded honestly)
does not depend on it.

### Verification run

- `zig fmt --check build.zig src tests`: clean.
- `zig build test --summary all`: 339/341 passed (2 pre-existing skips).
- `zig build test-mcp --summary all`: 82/83 passed (1 pre-existing skip).
- `zig build preview-gate --summary all`: 18/18 steps, 7/7 tests, all three
  profiles pass. Full hard-gate list collected and cross-checked: every
  gate named in `habit_loop_gate.md`'s table fired at least once, including
  all eight new ones and `honest_degradation`'s extended
  `working_copy.status: "in_sync"` assertion from Stage 3.
- Preflight-cost observations (all three profiles, this run): `fixture`
  first response 43 ms (7 units), `repository-copy` first response 590 ms
  (93 units, includes full index build, not just discovery), `sync-trust`
  first response 22 ms (9 units). Per-call latency after startup on
  `repository-copy` stays ~8-10 ms per graph-reading call (Stage 3's
  preflight cost), consistent with the Stage 3 observation.

### Stop-rule check

No stop condition triggered: the fail-closed contract was not weakened to a
metadata-only comparison anywhere, and preflight cost, while real, did not
make repeated reads unusable at the scale measured (single-digit to low
double-digit milliseconds per call).

**Done when:** the canonical preview gate reproduces and prevents the
original failure mode (done — `sync-trust` reproduces the exact ADR 014
regression shape and proves it now fails closed), and preflight cost is
recorded honestly (done, including the combined-with-startup caveat carried
over from Stage 3). Stage 5 complete except the external-repository
real-task evaluation, recorded above as a residual item.

## Stage 6: Canon, Review, And Closure

### Findings-first review

- **Source-state identity.** Re-read `src/source/identity.zig` end to end
  against ADR 014 D2's encoding order (version marker, budgets, sorted
  exclusions, sorted units with path/language/content, sorted diagnostics
  with kind/path/message). Matches. Strengthened during this stage: the
  cross-process claim was previously proven only as two scans inside one test
  process (`identity.zig`'s own test and the Stage 1 `discovery.scanDir`
  test); added two real two-server-process tests to `tests/mcp_smoke_test.zig`
  (same content, two processes, same identity; different content, two
  processes, same revision but different identity) that this stage required
  before closing Follow-up 021 — see below.
- **Failure retention.** Re-read `src/mcp/sync.zig`'s `reconcileFailed`/
  `rebuild` and confirmed against the exhaustive allocation-injection tests
  (`src/mcp/root.zig`, every allocation point of the sync path, one-shot and
  sticky) that every failure path leaves the previously published
  snapshot/identity pair intact and reports which recovery step completed. No
  finding.
- **Preflight ordering.** Re-read `callTool` in `src/mcp/root.zig`: preflight
  runs and `ctx` is populated before the tool switch is even evaluated for
  the six D4 tools, so a failing preflight structurally cannot reach a
  handler. No finding.
- **Cursor behavior.** The `sync-trust` gate profile's `cursor_restart` proof
  (a cursor issued before a revision-changing sync fails when retried after)
  relies on pre-existing cursor-revision binding, unmodified by this plan. No
  finding.
- **Jev blocking.** Structural, not a separate check: `semidx_rank_context`'s
  handler is one of the six behind the fails-closed switch, so a mismatch
  cannot reach `ranking.Provider.rank()`. Proven with a counting fake
  provider at the unit level (Stage 3); explicitly not proven by the stdio
  gate (documented in `habit_loop_gate.md`, not silently omitted). No
  additional finding beyond that documented scope boundary.
- **Error payloads.** Re-checked every `semidx_preflight_out_of_date`/
  `semidx_preflight_scan_failed` message against the plan's sanitization
  rule: neither includes the configured root's absolute path, source
  contents, or raw OS error text — only the stable prefix, the retained
  revision, and the retained `source_state_id`. No finding.

One real finding from this review, fixed in this stage: **Follow-up 021's
cross-process requirement was under-proven.** `identity.zig`'s own tests and
Stage 1's `discovery.scanDir` test both proved determinism by running two
scans *inside one test process*, which is sufficient evidence that the
encoding itself has no process-local input, but is not literally "two
servers" as Follow-up 021's Required Tests ask. Added, in
`tests/mcp_smoke_test.zig`: two real `semidx-mcp` subprocesses over the same
content report the same `source_state_id`; two real subprocesses over
different content report the same revision (proving revision alone still
cannot distinguish them) but different `source_state_id`; and one subprocess
restarted over unchanged content does not resume the revision it had before.
All three pass. Follow-up 021 is now marked `fixed`, `lifecycle: completed`,
with its own resolution section listing exactly which test proves which of
its four required tests.

### Drift control

Checked against the current owners the drift-control procedure names:

- `ARCHITECTURE_CONSTITUTION.md`: re-applied the §11 eight-question test to
  the delivered implementation, not just to ADR 014's text (Stage 0 checked
  the ADR's own reasoning; this pass checked the code against it). No
  deviation: `source_state_id` and `working_copy` are scan/comparison
  metadata, establish no relationship, and create no node.
- Accepted ADRs: ADR 014 accepted (Stage 0), text unchanged since. ADR 013
  cross-referenced (Plan 015's `semidx_rank_context` is one of the six
  preflight-gated tools) and confirmed still accurate: Plan 015's own
  progress log and `MEMORY.md` entry already say it remains blocked on Plan
  015 Stage 4 credentials, unaffected by this plan.
- `SPEC.md`: the "Working-copy synchronization" row (Stage 0) matches
  delivered behavior; no correction needed.
- `CONFORMANCE.md`: checked and intentionally left untouched. Its Required
  Scenario Families and Current Status section are graph/constitution
  evidence (entity identity, incrementality, consistent observation, and so
  on) for the core-slice plans (001-003); MCP-consumer plans such as 004
  (the MCP preview itself) and 015 (Jev) were never added there either. A
  working-copy trust boundary is consumer/presentation policy, not new
  graph-model evidence, so it does not belong in this document under its
  existing scope. Recorded here so the omission reads as a decision, not an
  oversight.
- `GLOSSARY.md`: **source-state identity**, **sync preflight**, and
  **working-copy status** (Stage 0) match delivered behavior; no correction
  needed.
- `MEMORY.md`: rewritten in this stage (see below) — the stage-by-stage
  narration accumulated across Stages 2-5 was compressed into final-state
  facts, the MCP tool list was corrected to finally include
  `semidx_rank_context` (a pre-existing omission from Plan 015, unrelated to
  this plan, fixed here since this stage's drift pass touched that exact
  bullet anyway), and the two now-resolved "known defect" bullets about
  revision-as-identity and `current`-as-sync were rewritten in the past
  tense with links to what replaced them.
- MCP docs (`docs/mcp/local_preview.md`, `docs/mcp/habit_loop_gate.md`):
  updated stage by stage already (Stages 2-5); re-read in full during this
  pass and found consistent with delivered behavior.
- Skills (`.agents/skills/semidx-code-exploration/SKILL.md`): updated in
  Stage 4; re-read and found consistent.
- Implementation, tests, gates: covered by the verification run below.

### Follow-up 021 closure

Marked `fixed` (see Findings-first review above for what closed it). Its
Required Tests are each named in its own updated "Resolution" section,
pointing at the exact test that proves it.

### Plan and progress-log closure

Every Definition of Done bullet re-checked against delivered evidence:

- ADR 014 accepted, `SPEC.md`/`GLOSSARY.md` own the vocabulary — Stage 0.
- Deterministic source-state identity, stable across equivalent processes —
  Stage 1, strengthened to real cross-process evidence in this stage.
- Every normal MCP result carries revision and source-state identity — Stage
  3 (`beginStructured` is shared by all nine tool result renderers).
- `semidx_sync` documented first call; unchanged sync preserves
  revision/ids/cursors; changed sync incremental, publishes once — Stages
  2 and 4.
- `semidx_refresh` remains a compatible alias — Stage 2.
- Health distinguishes `in_sync`/`out_of_date`/`scan_failed`, never mutates —
  Stages 3-4.
- Every graph-reading tool fails before rendering graph data on mismatch or
  failure, names `semidx_sync` — Stage 3.
- A fake enabled Jev provider receives zero calls when not `in_sync` — Stage
  3 (unit level; see the documented gate-level scope boundary above).
- Parser failure after a successful sync stays visible as
  stale/pending, distinct from working-copy mismatch — Stage 3.
- The external-edit regression, branch-switch batch, scan failure, no-op
  sync, changed sync, cursor restart, and recovery paths are hard-gate
  evidence — Stage 5 (`sync-trust` profile) plus the pre-existing recovery
  injection tests.
- Compact health is smaller than full while keeping every trust/parser
  signal — Stage 4 (25%).
- Verification stays offline and credential-free; preflight cost is recorded
  as an observation — every stage.
- Watchers, persistence, source rendering, stale bypass, release/version
  work, and public semantic contracts stayed outside scope — true throughout;
  no stage touched any of them.
- Implementation, docs, skills, ADR, follow-up status, plan, progress log,
  and `MEMORY.md` agree, and every coherent stage is committed — this stage.

The plan's Definition of Done does not name the external-repository real-task
evaluation as a required bullet (it appears only in Stage 5's "Required
work" list); closing the plan without it is therefore consistent with what
the plan itself commits to, not a lowered bar. It remains a genuine residual
item, offered to the operator as a follow-up rather than fabricated.

**Plan 016, this progress log, and ADR 014 are marked historical/completed
in the same commit as this stage**, per the documentation policy's closure
rule.

### Verification run

- `./scripts/check-zig-version.sh`: "Zig version 0.16.0 matches semidx
  target".
- `zig fmt --check build.zig src tests`: clean.
- `zig build test-core --summary all`: passed.
- `zig build test --summary all`: 342/344 passed (2 pre-existing skips),
  including the two new cross-process tests and the restart test.
- `zig build test-mcp --summary all`: passed.
- `zig build dogfood`: passed.
- `zig build preview-gate --summary all`: all three profiles pass.
- `./scripts/check-readme-stewardship.sh --all`: passed.
- `./scripts/check-memory-freshness.sh`: passed.

### Stop-rule check

No stop condition triggered in this stage: no release was published, no
stable MCP/semantic contract was claimed, and the one residual item was
disclosed rather than hidden.
