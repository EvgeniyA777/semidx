---
title: "Trustworthy working-copy synchronization progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-27"
---

# 016: Trustworthy Working-Copy Synchronization Progress

Companion log for
[docs/plans/016_trustworthy_working_copy_sync.md](../plans/016_trustworthy_working_copy_sync.md).

## Current Status

**Stages 0-1 complete.**

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
